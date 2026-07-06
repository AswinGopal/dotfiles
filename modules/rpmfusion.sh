#!/bin/bash

# modules/rpmfusion.sh
#
# Fedora only. Enable RPM Fusion repositories and configure multimedia codecs.
#
# Operations:
#   1. Install RPM Fusion free + nonfree repos for the current Fedora version.
#   2. Swap ffmpeg-free for ffmpeg (idempotent — skipped if already swapped).
#   3. Update the @multimedia group with weak deps disabled.
#   4. Install the GPU driver (default: intel-media-driver for Skylake+).
#
# Philosophy note: steps 1 and 4 use pkg_install(). Steps 2 and 3 call dnf
# directly — dnf swap and dnf update @multimedia carry flags and semantics
# that cannot be expressed through the pkg_install() interface. This is an
# intentional, documented exception. This module is Fedora-only.
#
# Must run before the packages module — enforced by os/fedora.sh MODULES order.
#
# Reads:
#   LOG_FILE — must be exported by install.sh; used by log_write in the
#              gum spin subprocess.
#
# Public interface: run_rpmfusion()

# ------------------------------------------------------------------------------
# run_rpmfusion
# ------------------------------------------------------------------------------
run_rpmfusion() {
    local fedora_ver
    fedora_ver=$(rpm -E %fedora) || {
        log_error "Failed to detect Fedora version via rpm -E %fedora."
        return 1
    }

    # pkg_install and log_write are bash functions; export them so the bash
    # subprocess spawned by gum spin can resolve them.
    export -f pkg_install
    export -f log_write

    # -- RPM Fusion free + nonfree repos ---------------------------------------
    run_with_spinner "Enabling RPM Fusion repositories..." \
        bash -c 'pkg_install "$@"' _ \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to enable RPM Fusion repositories."
        return 1
    fi
    success_message "RPM Fusion repositories enabled."

    # -- ffmpeg swap -----------------------------------------------------------
    # Idempotent: if ffmpeg is already installed, ffmpeg-free has already been
    # swapped out — running dnf swap again would fail. Skip in that case.
    if ! rpm -q ffmpeg &>/dev/null; then
        run_with_spinner "Swapping ffmpeg-free for ffmpeg..." \
            sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing

        if [[ $? -ne 0 ]]; then
            log_error "Failed to swap ffmpeg-free for ffmpeg."
            return 1
        fi
        success_message "ffmpeg swapped."
    fi

    # -- @multimedia group update ----------------------------------------------
    run_with_spinner "Installing multimedia codecs..." \
        sudo dnf update -y @multimedia \
        --setopt="install_weak_deps=False" \
        --exclude=PackageKit-gstreamer-plugin

    if [[ $? -ne 0 ]]; then
        log_error "Failed to install multimedia codecs."
        return 1
    fi
    success_message "Multimedia codecs installed."

    # -- GPU driver ------------------------------------------------------------
    # Intel (6th gen / Skylake and newer): intel-media-driver  [DEFAULT]
    # Intel (older than 6th gen):          libva-intel-driver
    # AMD:                                 mesa-va-drivers-freeworld
    # NVIDIA:                              libva-nvidia-driver
    run_with_spinner "Installing GPU driver..." \
        bash -c 'pkg_install "$@"' _ intel-media-driver

    if [[ $? -ne 0 ]]; then
        log_error "Failed to install GPU driver."
        return 1
    fi
    success_message "GPU driver installed."

    success_message "RPM Fusion and codecs configured."
    return 0
}
