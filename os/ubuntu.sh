#!/bin/bash

# os/ubuntu.sh
#
# Ubuntu Linux backend.
#
# Responsibilities:
#   1. Implement pkg_install() — overwrites the guard from lib/pkg.sh.
#   2. Implement pkg_remove() — overwrites the guard from lib/pkg.sh.
#   3. Declare MODULES — the ordered list of modules available on Ubuntu.
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
    if ! sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y "$@" > /dev/null; then
        log_write "ERROR" "apt-get failed to install: $*"
        printf 'Error: apt-get failed to install: %s\n' "$*" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# pkg_remove [package-or-pattern...]
#
# Remove one or more packages via apt-get. Each argument may be a literal
# package name or a shell-glob pattern (e.g. '*nvidia*', 'libreoffice-*').
#
# apt-get remove/purge cannot be trusted with a wildcard argument directly:
# a string containing a glob metacharacter is treated by apt as a POSIX
# extended regex, unanchored — not a shell glob. This was confirmed directly
# (not assumed): `apt-get remove --dry-run '.*apt.*'` attempted to select
# `apt` itself for removal, along with unrelated packages that merely
# contain the substring, and only stopped short of `apt` because -y without
# --allow-remove-essential blocked it. A bare literal name (no
# metacharacters) is unaffected — it resolves as an exact lookup, confirmed
# idempotent (apt-get purge on a real-but-uninstalled package exits 0,
# "is not installed, so not removed") — but any pattern needs to be kept
# away from apt's own matching engine entirely.
#
# This function therefore resolves every argument itself, in bash: glob-match
# it against the full list of currently-installed packages (dpkg-query -W),
# collect matches into an associative array (dedupes for free when two
# patterns overlap), and only ever pass apt-get real, confirmed-installed
# package names. An argument matching nothing installed — literal or
# pattern — is a silent no-op; apt-get is not even invoked if the resolved
# match set is empty. This also means a misspelled or nonexistent literal
# name can no longer hard-fail here the way a bare `apt-get remove` would.
#
# purge (not remove) deletes config files too, reclaiming the same ground
# pacman's -n flag already covers on Arch. Orphaned dependencies left behind
# are reclaimed separately by modules/remove_packages.sh's trailing
# `apt-get autoremove` pass, not by this function.
# ------------------------------------------------------------------------------
pkg_remove() {
    local -a installed
    mapfile -t installed < <(dpkg-query -W -f='${Package}\n' 2>/dev/null)

    local -A matched=()
    local pattern name
    for pattern in "$@"; do
        for name in "${installed[@]}"; do
            [[ "$name" == $pattern ]] && matched["$name"]=1
        done
    done

    local -a targets=("${!matched[@]}")

    # Nothing matched — idempotent no-op, apt-get is never invoked.
    [[ ${#targets[@]} -eq 0 ]] && return 0

    if ! sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get purge -y "${targets[@]}" > /dev/null; then
        log_write "ERROR" "apt-get failed to remove: ${targets[*]}"
        printf 'Error: apt-get failed to remove: %s\n' "${targets[*]}" >&2
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
    "remove_packages|Remove unwanted packages|on"
    "packages|Install packages|on"
    "bash|Bash & dotfiles|on"
    "shell_tools|Shell tools|on"
    "binaries|Binaries|on"
    "fonts|Fonts|on"
    "deno|Deno|on"
    "mpv|MPV|on"
    "browser_profiles|Browser profiles|on"
    "gnome_settings|GNOME Settings|on"
)
