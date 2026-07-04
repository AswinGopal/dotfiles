#!/bin/bash

# lib/pkg.sh
#
# Declares the pkg_install() interface contract and installs a guard
# implementation that fails loudly if called before os/<distro>.sh is sourced.
#
# ARCHITECTURE NOTE:
#   This file defines the interface. os/<distro>.sh defines the implementation.
#   install.sh sources os/<distro>.sh after this file, which overwrites the
#   guard with the real implementation. Sourcing order in install.sh is:
#
#     source lib/utils.sh
#     source lib/pkg.sh       ← guard installed
#     source os/$OS_ID.sh     ← real pkg_install() overwrites guard
#
# CONTRACT — every os/<distro>.sh implementation must satisfy:
#   - Accepts one or more package names as positional arguments
#   - Is idempotent: silently skips already-installed packages
#   - Suppresses routine stdout; errors surface to stderr
#   - Returns 0 on success, 1 on failure
#   - Never calls exit

pkg_install() {
    printf 'Error: pkg_install() called before os/<distro>.sh was sourced.\n' >&2
    printf 'This is a programming error in install.sh. Check sourcing order.\n' >&2
    exit 1
}
