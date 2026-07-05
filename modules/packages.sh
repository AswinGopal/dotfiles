#!/bin/bash

# modules/packages.sh
#
# Install all packages listed in packages/$OS_ID.txt via pkg_install().
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
# Install all collected packages in a single pkg_install() call wrapped in a
# spinner.
#
# pkg_install() and log_write() are bash functions. gum spin runs the wrapped
# command in a subprocess, so both must be exported before the spinner call.
# The array is passed through bash -c via positional parameters.
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

    run_with_spinner "Installing packages..." \
        bash -c 'pkg_install "$@"' _ "${packages[@]}"

    if [[ $? -ne 0 ]]; then
        log_error "Package installation failed."
        return 1
    fi

    success_message "Packages installed."
    return 0
}
