#!/bin/bash

# modules/remove_packages.sh
#
# Remove all packages/patterns listed in packages/remove-$OS_ID.txt via
# pkg_remove(), one entry at a time — structurally the mirror image of
# modules/packages.sh.
#
# Each line may be a literal package name or a shell-glob pattern (e.g.
# '*nvidia*', 'libreoffice-*'). Resolution against what's actually
# installed, and the differing safety concerns of pacman/dnf/apt-get, are
# entirely owned by each os/<distro>.sh's pkg_remove() implementation — this
# module stays agnostic to all of that, exactly as packages.sh stays
# agnostic to how pkg_install() does its job.
#
# Reads:
#   REPO_ROOT — set by install.sh (git rev-parse --show-toplevel)
#   OS_ID     — set by install.sh (arch | fedora | ubuntu)
#   LOG_FILE  — must be exported by install.sh; used by log_write inside the
#               gum spin subprocess.
#
# Public interface: run_remove_packages()

# ------------------------------------------------------------------------------
# _autoremove_orphans
#
# Reclaim dependency packages left orphaned by the removal loop above.
# Private to this module — called only by run_remove_packages, only after
# the loop completes.
#
# Arch is a deliberate no-op here: pkg_remove()'s `pacman -Rns` already
# removes now-unneeded dependencies inline, per call — there is nothing left
# for a separate pass to reclaim. Fedora's `dnf remove` and Ubuntu's
# `apt-get purge` have no equivalent flag, so orphans they leave behind
# require a distinct, separate command.
#
# This is a direct, OS-branched package-manager call rather than something
# expressed through pkg_install()/pkg_remove() — the same kind of documented
# exception modules/rpmfusion.sh already takes for `dnf swap` and
# `dnf update @multimedia`, which likewise have no equivalent in the
# pkg_install() interface. OS_ID branching inside an otherwise shared module
# is also not new here — modules/browser_profiles.sh already does the same
# for firefox_profile_dir.
#
# Returns: 0 on success or on Arch's no-op, 1 if the autoremove call failed.
# ------------------------------------------------------------------------------
_autoremove_orphans() {
    case "$OS_ID" in
        arch)
            return 0
            ;;
        fedora)
            if ! sudo dnf autoremove -y > /dev/null; then
                log_error "Failed to autoremove orphaned dependencies."
                return 1
            fi
            ;;
        ubuntu)
            if ! sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get autoremove -y > /dev/null; then
                log_error "Failed to autoremove orphaned dependencies."
                return 1
            fi
            ;;
        *)
            log_error "remove_packages: unsupported OS_ID '$OS_ID'."
            return 1
            ;;
    esac

    return 0
}

# ------------------------------------------------------------------------------
# run_remove_packages
#
# Read packages/remove-$OS_ID.txt line by line, skipping blank lines and
# comments. All entries are attempted regardless of individual failures. The
# module returns 1 if any entry failed or the trailing autoremove pass
# failed, so the user is alerted via show_summary, but execution continues
# to ensure every entry gets a chance to run.
#
# pkg_remove() and log_write() are bash functions. gum spin runs the wrapped
# command in a subprocess, so both must be exported before the spinner calls.
# ------------------------------------------------------------------------------
run_remove_packages() {
    local pkg_file="$REPO_ROOT/packages/remove-$OS_ID.txt"

    if [[ ! -f "$pkg_file" ]]; then
        log_error "Removal list not found: $pkg_file"
        return 1
    fi

    local -a entries=()
    local line
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == '#'* ]] && continue
        entries+=("$line")
    done < "$pkg_file"

    if [[ ${#entries[@]} -eq 0 ]]; then
        log_error "Removal list is empty: $pkg_file"
        return 1
    fi

    # pkg_remove and log_write are bash functions; export them so the bash
    # subprocess spawned by gum spin can resolve them.
    export -f pkg_remove
    export -f log_write

    local failed=0
    local entry

    for entry in "${entries[@]}"; do
        run_with_spinner "Removing $entry..." \
            bash -c 'pkg_remove "$@"' _ "$entry"

        if [[ $? -ne 0 ]]; then
            log_error "Failed to remove $entry."
            failed=1
        fi
    done

    if ! _autoremove_orphans; then
        failed=1
    fi

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "Unwanted packages removed."
    return 0
}
