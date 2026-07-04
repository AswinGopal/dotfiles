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