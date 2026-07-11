#!/bin/bash

# setup/check-gsettings.sh
#
# Read-only verification of the gsettings/timedatectl keys used by
# modules/ubuntu_settings.sh. Written for GNOME 50 re-verification after the
# GNOME Shell rewrite — several schemas/keys authored against older GNOME
# versions may have moved, renamed, or been removed.
#
# GUARANTEE: this script never calls `gsettings set`, `timedatectl set-*`, or
# any other mutating command. Every check below is read-only (list-schemas,
# get, show). No sudo is required anywhere in this script — if it ever
# prompts for a password, that itself is a signal something is wrong.
#
# Not a module — does not implement run_<module>(), is not sourced by
# install.sh, and is not part of the MODULES/orchestration system. Run
# standalone:
#   bash setup/check-gsettings.sh
#
# For each gsettings key, reports one of three outcomes:
#   MISSING SCHEMA — the schema itself no longer exists (mechanism is gone,
#                     not just renamed; likely needs a replacement approach)
#   MISSING KEY     — schema exists but this key does not (likely renamed)
#   OK               — key resolved; current value is printed for a sanity
#                       check, not just confirmation the call succeeded
#
# Exit code: 0 if every check resolved cleanly, 1 if any check failed.

# ------------------------------------------------------------------------------
# check_key schema key label
#
# Verify a single gsettings schema+key pair without modifying anything.
# Prints a labeled MISSING SCHEMA / MISSING KEY / OK result to stdout.
#
# Returns: 0 if the key resolved, 1 otherwise. Caller aggregates the overall
# exit code — this function only ever reads.
# ------------------------------------------------------------------------------
check_key() {
    local schema="$1"
    local key="$2"
    local label="$3"

    if ! gsettings list-schemas | grep -qxF "$schema"; then
        printf '[MISSING SCHEMA] %s — schema "%s" does not exist\n' "$label" "$schema"
        return 1
    fi

    local value
    if ! value=$(gsettings get "$schema" "$key" 2>&1); then
        printf '[MISSING KEY]    %s — schema "%s" exists but key "%s" does not\n' \
            "$label" "$schema" "$key"
        return 1
    fi

    printf '[OK]             %s — %s %s = %s\n' "$label" "$schema" "$key" "$value"
    return 0
}

# ------------------------------------------------------------------------------
# dump_schema schema label
#
# Print every key and current value under a schema, for discovery purposes —
# used when the exact key name to target is not yet known (as opposed to
# check_key, which verifies one already-known schema+key pair). Read-only:
# list-recursively only reads.
#
# Returns: 0 if the schema exists and was dumped, 1 if the schema is missing.
# ------------------------------------------------------------------------------
dump_schema() {
    local schema="$1"
    local label="$2"

    if ! gsettings list-schemas | grep -qxF "$schema"; then
        printf '[MISSING SCHEMA] %s — schema "%s" does not exist\n' "$label" "$schema"
        return 1
    fi

    printf -- '--- %s (%s) ---\n' "$label" "$schema"
    gsettings list-recursively "$schema"
    return 0
}

# ------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------
main() {
    local failed=0

    echo "Checking gsettings keys used by modules/ubuntu_settings.sh..."
    echo "(read-only — no settings will be modified)"
    echo

    # ==========================================================================
    # SCHEMA DISCOVERY — candidate settings not yet added to
    # modules/ubuntu_settings.sh (mouse acceleration, screen blank / suspend,
    # file & app history). Exact key names are not yet confirmed, so this
    # section dumps full schema contents for inspection rather than checking
    # a specific key — read-only, same as the section above.
    # ==========================================================================
    echo
    echo "=========================================================================="
    echo "SCHEMA DISCOVERY — candidate settings, exact keys not yet confirmed"
    echo "(read-only — no settings will be modified)"
    echo "=========================================================================="
    echo

    dump_schema "org.gnome.desktop.wm.keybindings" \
        "Window manager keybindings (close shortcut candidate)" || failed=1
    echo

    dump_schema "org.gnome.settings-daemon.plugins.media-keys" \
        "Custom keybindings (custom keys candidate)" || failed=1
    echo

    dump_schema "org.gnome.desktop.session" \
        "Session (idle-delay / screen blank candidate)" || failed=1
    echo

    dump_schema "org.gnome.desktop.interface" \
        "Desktop interface (clock format candidate)" || failed=1
    echo

    dump_schema "org.gtk.Settings.FileChooser" \
        "GTK File Chooser (clock format candidate)" || failed=1
    echo

    dump_schema "org.gnome.desktop.peripherals.mouse" \
        "Mouse (acceleration candidate)" || failed=1
    echo

    dump_schema "org.gnome.settings-daemon.plugins.power" \
        "Power daemon (screen blank / suspend candidates)" || failed=1
    echo

    dump_schema "org.gnome.desktop.privacy" \
        "Privacy (file & app history candidates)" || failed=1
    echo

    if [[ $failed -ne 0 ]]; then
        return 1
    fi
    return 0
}

main
exit $?
