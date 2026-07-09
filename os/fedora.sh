#!/bin/bash

# os/fedora.sh
#
# Fedora Linux backend.
#
# Responsibilities:
#   1. Implement pkg_install() — overwrites the guard from lib/pkg.sh.
#   2. Declare MODULES — the ordered list of modules available on Fedora.
#
# Sourced by install.sh at step 4, before gum is available.
# lib/utils.sh (log_write) is already sourced at step 2.
# lib/ui.sh (log_error, show_info, success_message) is NOT yet available here.

# ------------------------------------------------------------------------------
# pkg_install [package...]
#
# Install one or more packages via dnf.
# -y          → non-interactive.
# Idempotency is native to dnf — already-installed packages are skipped.
# stdout suppressed; stderr passes through for error visibility.
# ------------------------------------------------------------------------------
pkg_install() {
    if ! sudo dnf install -y "$@" > /dev/null; then
        log_write "ERROR" "dnf failed to install: $*"
        printf 'Error: dnf failed to install: %s\n' "$*" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# MODULES
#
# Ordered list of modules available on Fedora.
# Format: "key|Display Label|default"   (default: on | off)
#
# NOTE: rpmfusion is listed first — packages/fedora.txt includes packages from
# RPM Fusion repos (e.g. intel-media-driver), so those repos must be enabled
# before the packages module runs.
# ------------------------------------------------------------------------------
MODULES=(
    "rpmfusion|RPM Fusion & Codecs|on"
    "packages|Install packages|on"
    "bash|Bash & dotfiles|on"
    "shell_tools|Shell tools|on"
    "binaries|Binaries|on"
    "desktop_entries|Desktop entries|on"
    "deno|Deno|on"
    "fonts|Fonts|on"
    "mpv|MPV|on"
    "browser_profiles|Browser profiles|on"
    "firewall|Firewall|on"
    "gnome_settings|GNOME Settings|on"
)
