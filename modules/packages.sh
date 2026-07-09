#!/bin/bash

# modules/packages.sh
#
# Install all packages listed in packages/$OS_ID.txt via pkg_install(),
# one package at a time.
#
# Reads:
#   REPO_ROOT — set by install.sh (git rev-parse --show-toplevel)
#   OS_ID     — set by install.sh (arch | fedora | ubuntu)
#   LOG_FILE  — must be exported by install.sh; used by log_write inside the
#               gum spin subprocess.
#
# Public interface: run_packages()

# ------------------------------------------------------------------------------
# run_packages
#
# Read packages/$OS_ID.txt line by line, skipping blank lines and comments.
# All packages are attempted regardless of individual failures. The module
# returns 1 if any package failed to install so the user is alerted via
# show_summary, but execution continues to ensure every package gets a
# chance to install.
#
# pkg_install() and log_write() are bash functions. gum spin runs the wrapped
# command in a subprocess, so both must be exported before the spinner calls.
# ------------------------------------------------------------------------------
run_packages() {
    local pkg_file="$REPO_ROOT/packages/$OS_ID.txt"

    if [[ ! -f "$pkg_file" ]]; then
        log_error "Package list not found: $pkg_file"
        return 1
    fi

    local -a packages=()
    local line
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == '#'* ]] && continue
        packages+=("$line")
    done < "$pkg_file"

    if [[ ${#packages[@]} -eq 0 ]]; then
        log_error "Package list is empty: $pkg_file"
        return 1
    fi

    # pkg_install and log_write are bash functions; export them so the bash
    # subprocess spawned by gum spin can resolve them.
    export -f pkg_install
    export -f log_write

    local failed=0
    local package

    for package in "${packages[@]}"; do
        run_with_spinner "Installing $package..." \
            bash -c 'pkg_install "$@"' _ "$package"

        if [[ $? -ne 0 ]]; then
            log_error "Failed to install $package."
            failed=1
        fi
    done

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "Packages installed."
    return 0
}
