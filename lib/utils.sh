#!/bin/bash

# lib/utils.sh
#
# Pure utility functions. No external dependencies beyond bash and POSIX tools.
# Sourced before gum, pkg_install, and OS detection are available.
#
# Requires:
#   LOG_FILE — set by install.sh before sourcing this file.
#              Falls back to /dev/null if unset (safe for standalone sourcing).

# ------------------------------------------------------------------------------
# log_write LEVEL "message"
#
# Write a timestamped entry to $LOG_FILE.
# Not for direct use by modules — called internally by ui.sh and download_binary.
# ------------------------------------------------------------------------------
log_write() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %T")
    printf '[%s] %s: %s\n' "$timestamp" "$level" "$message" >> "${LOG_FILE:-/dev/null}"
}

# ------------------------------------------------------------------------------
# download_binary "name" "url" "dest"
#
# Download a binary from a URL to a destination path and make it executable.
# Idempotent: skips silently if dest already exists and is executable.
# Error output goes to stderr and the log — never to stdout.
# Caller is responsible for ensuring the destination directory exists.
#
# Returns: 0 on success, 1 on failure.
# ------------------------------------------------------------------------------
download_binary() {
    local name="$1"
    local url="$2"
    local dest="$3"

    if [ -f "$dest" ] && [ -x "$dest" ]; then
        return 0
    fi

    if ! curl -fsSL "$url" -o "$dest"; then
        log_write "ERROR" "Failed to download $name from $url"
        echo "Error: Failed to download $name." >&2
        return 1
    fi

    chmod +x "$dest"
    return 0
}

# ------------------------------------------------------------------------------
# append_if_missing "file" "marker" "content"
#
# Append a block of content to a file if the marker string is not already
# present. Uses fixed-string matching — no regex interpretation of the marker.
# Idempotent: safe to call on every run.
#
# Does NOT create the file if it is missing — a missing target is an upstream
# error and should surface, not be silently masked.
#
# Returns: 0 on success or if marker already present, 1 if file does not exist.
# ------------------------------------------------------------------------------
append_if_missing() {
    local file="$1"
    local marker="$2"
    local content="$3"

    if [ ! -f "$file" ]; then
        log_write "ERROR" "append_if_missing: file does not exist: $file"
        echo "Error: Target file does not exist: $file" >&2
        return 1
    fi

    if grep -qF "$marker" "$file"; then
        return 0
    fi

    printf '\n%s\n' "$content" >> "$file"
    return 0
}

# ------------------------------------------------------------------------------
# gsettings_set_if_changed "schema" "key" "value"
#
# Set a gsettings key only if its current value differs from the target.
# gsettings set fires a change-notify signal on the D-Bus even when the
# written value is unchanged, which can cause visible side effects (GNOME
# Shell / listening apps re-reading config, brief redraws) on an already-
# configured system. Checking first avoids that on repeat runs.
#
# Comparison is a plain string comparison against `gsettings get` output
# (e.g. "'12h'", "true", "uint32 0"). This is sufficient for the scalar
# types (booleans, strings, enums, single integers) this function is used
# for. It is not intended for array or tuple-typed keys.
#
# If the current value cannot be read (missing schema/key), the write is
# attempted anyway — gsettings set will itself fail cleanly and report the
# real error, rather than this function guessing at why the read failed.
#
# Returns: 0 if the value already matched, or was successfully set.
#          1 if the set was attempted and failed.
# ------------------------------------------------------------------------------
gsettings_set_if_changed() {
    local schema="$1"
    local key="$2"
    local value="$3"

    local current
    if current=$(gsettings get "$schema" "$key" 2>/dev/null) && [ "$current" = "$value" ]; then
        return 0
    fi

    if ! gsettings set "$schema" "$key" "$value"; then
        log_write "ERROR" "Failed to set $schema $key to $value"
        echo "Error: Failed to set $schema $key." >&2
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# timedatectl_set_timezone_if_changed "timezone"
#
# Set the system timezone only if it differs from the target. Same
# rationale as gsettings_set_if_changed — avoid an unnecessary write (and
# the sudo prompt / systemd-timedated signal that comes with it) when the
# timezone is already correct.
#
# Requires sudo for the write path only — the read is unprivileged.
#
# Returns: 0 if the timezone already matched, or was successfully set.
#          1 if the set was attempted and failed.
# ------------------------------------------------------------------------------
timedatectl_set_timezone_if_changed() {
    local timezone="$1"

    local current
    current=$(timedatectl show -p Timezone --value 2>/dev/null)

    if [ "$current" = "$timezone" ]; then
        return 0
    fi

    if ! sudo timedatectl set-timezone "$timezone"; then
        log_write "ERROR" "Failed to set timezone to $timezone"
        echo "Error: Failed to set timezone to $timezone." >&2
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------------------
# is_gnome_session
#
# Predicate: does the current session report GNOME as the desktop
# environment? Checks XDG_CURRENT_DESKTOP, the variable defined by the
# Desktop Entry Specification for exactly this purpose. Per spec, its value
# is a colon-separated list (e.g. Ubuntu sets "ubuntu:GNOME") — matched as
# a delimited token, not a substring, so a hypothetical future desktop name
# that merely contains "GNOME" cannot false-match.
#
# XDG_CURRENT_DESKTOP is a session variable: it is only exported once a
# graphical session is running. If unset (e.g. run from a bare TTY, over
# SSH, or before a desktop session starts), this returns 1 — treating
# "unknown" the same as "not GNOME" is the safe default for callers that
# gate GNOME-specific writes.
#
# Pure predicate — no logging, no side effects.
#
# Returns: 0 if GNOME is the current desktop, 1 otherwise.
# ------------------------------------------------------------------------------
is_gnome_session() {
    [[ ":${XDG_CURRENT_DESKTOP}:" == *:GNOME:* ]]
}