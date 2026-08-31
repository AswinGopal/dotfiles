#!/bin/bash

# lib/pkg.sh
#
# Declares the pkg_install()/pkg_remove() interface contracts and installs
# guard implementations that fail loudly if called before os/<distro>.sh is
# sourced.
#
# ARCHITECTURE NOTE:
#   This file defines the interface. os/<distro>.sh defines the implementation.
#   install.sh sources os/<distro>.sh after this file, which overwrites the
#   guards with the real implementations. Sourcing order in install.sh is:
#
#     source lib/utils.sh
#     source lib/pkg.sh       ← guards installed
#     source os/$OS_ID.sh     ← real pkg_install()/pkg_remove() overwrite guards
#
# CONTRACT — every os/<distro>.sh implementation of pkg_install() must satisfy:
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

# CONTRACT — every os/<distro>.sh implementation of pkg_remove() must satisfy:
#   - Accepts one or more arguments, each either a literal package name or a
#     shell-glob pattern (e.g. '*nvidia*', 'libreoffice-*')
#   - Idempotent by construction: every argument is resolved against the set
#     of packages currently installed before anything is touched. An
#     argument that matches nothing installed — already absent, never
#     installed, misspelled, or a pattern that simply matches nothing — is a
#     silent no-op, never a failure. Removal is never attempted based on a
#     package manager's own knowledge of whether a name exists anywhere in
#     its repo metadata, only against what is actually present on the system.
#   - Suppresses routine stdout; errors surface to stderr
#   - Returns 0 on success (including "nothing matched"), 1 on failure
#   - Never calls exit
#
# IMPLEMENTATION NOTE:
#   dnf's own remove resolution already satisfies this contract natively —
#   its glob matching is anchored to the full package name and scoped to the
#   installed rpmdb only — so Fedora's implementation passes arguments
#   straight through. pacman -R and apt-get remove/purge do not: pacman
#   hard-fails on an already-absent target, and apt's own pattern matching is
#   unanchored POSIX regex, not a shell glob — a broad pattern can match far
#   more than intended, up to and including essential packages. Arch's and
#   Ubuntu's implementations therefore resolve every argument themselves, in
#   bash, against their own installed-package listing (pacman -Qq /
#   dpkg-query -W) before calling pacman -Rns / apt-get purge on the
#   resolved literal names only.

pkg_remove() {
    printf 'Error: pkg_remove() called before os/<distro>.sh was sourced.\n' >&2
    printf 'This is a programming error in install.sh. Check sourcing order.\n' >&2
    exit 1
}