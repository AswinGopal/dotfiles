#!/bin/bash

# os/fedora.sh
#
# Fedora Linux backend.
#
# Responsibilities:
#   1. Implement pkg_install() — overwrites the guard from lib/pkg.sh.
#   2. Implement pkg_remove() — overwrites the guard from lib/pkg.sh.
#   3. Declare MODULES — the ordered list of modules available on Fedora.
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
# pkg_remove [package-or-pattern...]
#
# Remove one or more packages via dnf. Each argument may be a literal
# package name or a shell-glob pattern (e.g. '*nvidia*', 'libreoffice-*').
#
# Unlike pacman -R and apt-get remove/purge, dnf's own remove resolution
# already satisfies the contract in lib/pkg.sh natively: it matches purely
# against the installed rpmdb (never against repo metadata), and its glob
# matching is anchored to the full package name — so arguments are passed
# straight through, with no bash-side resolution needed. A literal name or
# pattern that matches nothing installed resolves to "No packages marked for
# removal" and exits 0; this is true whether the name is real or a typo,
# since dnf never consults repo metadata for a remove operation.
#
# Idempotency is therefore free here. No -Rns/autoremove-equivalent flag
# exists on `dnf remove` itself — orphaned dependencies left behind by this
# call are reclaimed separately by modules/remove_packages.sh's trailing
# `dnf autoremove` pass, not by this function.
# ------------------------------------------------------------------------------
pkg_remove() {
    if ! sudo dnf remove -y "$@" > /dev/null; then
        log_write "ERROR" "dnf failed to remove: $*"
        printf 'Error: dnf failed to remove: %s\n' "$*" >&2
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
# NOTE: remove_packages is listed first — ahead of rpmfusion too, not just
# packages. rpmfusion's own module installs the RPM Fusion release packages
# and runs `dnf update -y @multimedia`, which fetches/updates a chunk of
# multimedia packages of its own; running removal after that would mean
# paying the bandwidth cost for packages about to be deleted anyway.
#
# rpmfusion is listed second — packages/fedora.txt includes packages from
# RPM Fusion repos (e.g. intel-media-driver), so those repos must be enabled
# before the packages module runs.
# ------------------------------------------------------------------------------
MODULES=(
    "remove_packages|Remove unwanted packages|on"
    "rpmfusion|RPM Fusion & Codecs|on"
    "packages|Install packages|on"
    "bash|Bash & dotfiles|on"
    "shell_tools|Shell tools|on"
    "binaries|Binaries|on"
    "deno|Deno|on"
    "fonts|Fonts|on"
    "mpv|MPV|on"
    "browser_profiles|Browser profiles|on"
    "firewall|Firewall|on"
    "gnome_settings|GNOME Settings|on"
)
