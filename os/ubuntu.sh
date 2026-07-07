#!/bin/bash

# os/ubuntu.sh
#
# Ubuntu Linux backend.
#
# Responsibilities:
#   1. Implement pkg_install() — overwrites the guard from lib/pkg.sh.
#   2. Declare MODULES — the ordered list of modules available on Ubuntu.
#
# Sourced by install.sh at step 4, before gum is available.
# lib/utils.sh (log_write) is already sourced at step 2.
# lib/ui.sh (log_error, show_info, success_message) is NOT yet available here.

# ------------------------------------------------------------------------------
# pkg_install [package...]
#
# Install one or more packages via apt-get.
# -y          → non-interactive.
# Idempotency is native to apt-get — already-installed packages are skipped.
# stdout suppressed; stderr passes through for error visibility.
# ------------------------------------------------------------------------------
pkg_install() {
    if ! sudo apt-get install -y "$@" > /dev/null; then
        log_write "ERROR" "apt-get failed to install: $*"
        printf 'Error: apt-get failed to install: %s\n' "$*" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# MODULES
#
# Ordered list of modules available on Ubuntu.
# Format: "key|Display Label|default"   (default: on | off)
# ------------------------------------------------------------------------------
MODULES=(
    "packages|Install packages|on"
    "bash|Bash & dotfiles|on"
    "shell_tools|Shell tools|on"
    "binaries|Binaries|on"
    "fonts|Fonts|on"
    "deno|Deno|on"
    "mpv|MPV|on"
    "browser_profiles|Browser profiles|on"
    "ubuntu_settings|GNOME Settings|on"
)
