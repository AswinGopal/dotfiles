#!/bin/bash

# os/arch.sh
#
# Arch Linux backend.
#
# Responsibilities:
#   1. Implement pkg_install() — overwrites the guard from lib/pkg.sh.
#   2. Declare MODULES — the ordered list of modules available on Arch.
#
# Sourced by install.sh at step 4, before gum is available.
# lib/utils.sh (log_write) is already sourced at step 2.
# lib/ui.sh (log_error, show_info, success_message) is NOT yet available here.

# ------------------------------------------------------------------------------
# pkg_install [package...]
#
# Install one or more packages via pacman.
# --needed   → idempotent: skips packages already at the correct version.
# --noconfirm → non-interactive.
# stdout suppressed; stderr passes through for error visibility.
# ------------------------------------------------------------------------------
pkg_install() {
    if ! sudo pacman -S --noconfirm --needed "$@" > /dev/null; then
        log_write "ERROR" "pacman failed to install: $*"
        printf 'Error: pacman failed to install: %s\n' "$*" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# MODULES
#
# Ordered list of modules available on Arch.
# Format: "key|Display Label|default"   (default: on | off)
# ------------------------------------------------------------------------------
MODULES=(
    "packages|Install packages|on"
    "bash|Bash & dotfiles|on"
    "shell_tools|Shell tools|on"
    "binaries|Binaries|on"
    "desktop_entries|Desktop entries|on"
    "deno|Deno|on"
    "fonts|Fonts|on"
    "mpv|MPV|on"
    "browser_profiles|Browser profiles|on"
    "gnome_settings|GNOME Settings|on"
    "secure_boot|Secure Boot scripts|off"
)