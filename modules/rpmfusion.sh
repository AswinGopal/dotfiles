#!/bin/bash

# modules/rpmfusion.sh
#
# Fedora only. Enable RPM Fusion repositories and configure multimedia codecs.
#
# Operations:
#   1. Install RPM Fusion free + nonfree repos for the current Fedora version.
#   2. Swap ffmpeg-free for ffmpeg (idempotent — skipped if already swapped).
#   3. Update the @multimedia group with weak deps disabled.
#   4. Detect the primary GPU vendor (AMD or Intel) and install the
#      corresponding driver (default: intel-media-driver for Skylake+).
#
# Philosophy note: steps 1 and 4's install use pkg_install(). Steps 2 and 3,
# and the AMD vulkan-driver swap in step 4, call dnf directly — dnf swap and
# dnf update @multimedia carry flags and semantics that cannot be expressed
# through the pkg_install() interface. This is an intentional, documented
# exception. This module is Fedora-only.
#
# Must run before the packages module — enforced by os/fedora.sh MODULES order.
#
# GPU vendor is read from the primary display controller (lspci), not the
# CPU: on an APU the two coincide, but they need not on a system with a
# discrete GPU. Detection requires pciutils (provides lspci), which is not
# listed in packages/fedora.txt — this module installs it itself, the same
# self-contained-dependency pattern modules/shell_tools.sh uses for
# zoxide/fzf/uv. Dual-GPU/hybrid systems are out of scope: only the first
# display controller lspci reports is considered. Anything other than AMD
# (including NVIDIA, which has no implementation yet) falls through to the
# Intel branch.
#
# Reads:
#   LOG_FILE — must be exported by install.sh; used by log_write in the
#              gum spin subprocess.
#
# Public interface: run_rpmfusion()

# ------------------------------------------------------------------------------
# _detect_gpu_vendor
#
# Detect the primary GPU vendor via lspci, scoped to VGA/3D-controller class
# entries. Only AMD and Intel are distinguished — anything else (NVIDIA, an
# unrecognized string, or lspci itself failing to run or to match) falls
# through to "intel", matching intel-media-driver's existing status as this
# module's documented [DEFAULT] driver.
#
# Dual-GPU/hybrid systems are explicitly out of scope: if lspci reports more
# than one display controller, this takes the first match in lspci's listing
# order and does not attempt to identify a "primary" GPU.
#
# Caller is responsible for ensuring pciutils (lspci) is installed first.
#
# Never fails. Prints "amd" or "intel" to stdout.
# ------------------------------------------------------------------------------
_detect_gpu_vendor() {
    local gpu_line
    gpu_line=$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller' | head -1)

    if [[ "$gpu_line" =~ (AMD|ATI|Advanced Micro Devices) ]]; then
        echo "amd"
    else
        echo "intel"
    fi
}

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
    # Idempotent: skip if ffmpeg is already present. based on the assumption that 
    # rpmfusion is run at the beginning of the setup process. this might fail if
    # rpmfusion module was ran on a system where ffmpeg was installed by other means.
    if rpm -q ffmpeg &>/dev/null; then
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
        sudo dnf install -y @multimedia \
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
    # AMD:                                 mesa-va-drivers-freeworld (+ vulkan swap)
    # NVIDIA:                              libva-nvidia-driver (not implemented — falls through to Intel)
    #
    # pciutils (lspci) isn't in packages/fedora.txt, so it's installed here,
    # immediately before the vendor detection that needs it.
    run_with_spinner "Installing pciutils..." \
        bash -c 'pkg_install "$@"' _ pciutils

    if [[ $? -ne 0 ]]; then
        log_error "Failed to install pciutils."
        return 1
    fi

    local gpu_vendor
    gpu_vendor=$(_detect_gpu_vendor)

    if [[ "$gpu_vendor" == "amd" ]]; then
        run_with_spinner "Installing GPU driver..." \
            bash -c 'pkg_install "$@"' _ mesa-va-drivers-freeworld

        if [[ $? -ne 0 ]]; then
            log_error "Failed to install GPU driver."
            return 1
        fi

        # Idempotent: skip if mesa-vulkan-drivers (non-freeworld) is no longer
        # present — the swap has already run. Mirrors the ffmpeg-free check
        # above.
        if rpm -q mesa-vulkan-drivers &>/dev/null; then
            run_with_spinner "Swapping mesa-vulkan-drivers for freeworld variant..." \
                sudo dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld

            if [[ $? -ne 0 ]]; then
                log_error "Failed to swap mesa-vulkan-drivers for freeworld variant."
                return 1
            fi
        fi
    else
        run_with_spinner "Installing GPU driver..." \
            bash -c 'pkg_install "$@"' _ intel-media-driver

        if [[ $? -ne 0 ]]; then
            log_error "Failed to install GPU driver."
            return 1
        fi
    fi

    success_message "GPU driver installed."

    success_message "RPM Fusion and codecs configured."
    return 0
}
