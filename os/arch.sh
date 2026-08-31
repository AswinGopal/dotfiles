#!/bin/bash

# os/arch.sh
#
# Arch Linux backend.
#
# Responsibilities:
#   1. Implement pkg_install() — overwrites the guard from lib/pkg.sh.
#   2. Implement pkg_remove() — overwrites the guard from lib/pkg.sh.
#   3. Declare MODULES — the ordered list of modules available on Arch.
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
# pkg_remove [package-or-pattern...]
#
# Remove one or more packages via pacman. Each argument may be a literal
# package name or a shell-glob pattern (e.g. '*nvidia*', 'libreoffice-*').
#
# pacman -R has no wildcard support and hard-fails (`target not found`) on an
# already-absent target, so this function resolves every argument itself:
# glob-match it against the full list of currently-installed packages
# (pacman -Qq), collect the matches into an associative array (dedupes for
# free when two patterns overlap), and only ever pass pacman real, confirmed-
# installed package names. An argument matching nothing installed — literal
# or pattern — is therefore a silent no-op, never a failure; pacman -Rns is
# not even invoked if the resolved match set is empty.
#
# -Rns: R(emove), n(o save — delete config files, no .pacsave), s(recursive —
# also remove now-unneeded dependencies of what's being removed). This means
# orphaned dependencies are reclaimed inline, per-call — unlike Fedora/Ubuntu,
# Arch needs no separate autoremove-equivalent pass.
# ------------------------------------------------------------------------------
pkg_remove() {
    local -a installed
    mapfile -t installed < <(pacman -Qq)

    local -A matched=()
    local pattern name
    for pattern in "$@"; do
        for name in "${installed[@]}"; do
            [[ "$name" == $pattern ]] && matched["$name"]=1
        done
    done

    local -a targets=("${!matched[@]}")

    # Nothing matched — idempotent no-op, pacman is never invoked.
    [[ ${#targets[@]} -eq 0 ]] && return 0

    if ! sudo pacman -Rns --noconfirm "${targets[@]}" > /dev/null; then
        log_write "ERROR" "pacman failed to remove: ${targets[*]}"
        printf 'Error: pacman failed to remove: %s\n' "${targets[*]}" >&2
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# MODULES
#
# Ordered list of modules available on Arch.
# Format: "key|Display Label|default"   (default: on | off)
#
# NOTE: remove_packages is listed first — it must run before anything else
# touches the package manager, so nothing gets installed or updated (e.g. via
# a later module's package operations) only to be immediately removed.
# ------------------------------------------------------------------------------
MODULES=(
    "remove_packages|Remove unwanted packages|on"
    "packages|Install packages|on"
    "bash|Bash & dotfiles|on"
    "shell_tools|Shell tools|on"
    "binaries|Binaries|on"
    "deno|Deno|on"
    "fonts|Fonts|on"
    "mpv|MPV|on"
    "browser_profiles|Browser profiles|on"
    "gnome_settings|GNOME Settings|on"
    "secure_boot|Secure Boot scripts|off"
)
