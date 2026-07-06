#!/bin/bash

# modules/binaries.sh
#
# Download binaries to $HOME/.local/bin.
#
# To add a binary: append a "name url" entry to _BINARIES. The binary is
# installed as $HOME/.local/bin/<name>. Names and URLs must not contain spaces.
#
# All downloads are attempted regardless of individual failures. The module
# returns 1 if any download failed so the user is alerted via show_summary,
# but execution continues to ensure every binary gets a chance to install.
#
# Idempotency is provided by download_binary() in lib/utils.sh — each binary
# is skipped silently if it already exists and is executable.
#
# Reads:
#   LOG_FILE — must be exported by install.sh; used by log_write in the
#              gum spin subprocess.
#
# Public interface: run_binaries()

# To add a binary: one line here. Format: "name url"
_BINARIES=(
    "yt-dlp        https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
    "git_info      https://github.com/AswinGopal/git_info/releases/latest/download/git_info"
    "ytdownloader  https://github.com/AswinGopal/ytdownloader/releases/latest/download/ytdownloader"
)

# ------------------------------------------------------------------------------
# run_binaries
#
# Ensure $HOME/.local/bin exists, export the bash functions needed by the gum
# spin subprocess, then download each binary via a dedicated spinner call.
# ------------------------------------------------------------------------------
run_binaries() {
    local bin_dir="$HOME/.local/bin"

    mkdir -p "$bin_dir" || { log_error "Failed to create $bin_dir"; return 1; }

    # download_binary and log_write are bash functions; export them so the bash
    # subprocess spawned by gum spin can resolve them.
    export -f download_binary
    export -f log_write

    local failed=0
    local entry name url

    for entry in "${_BINARIES[@]}"; do
        read -r name url <<< "$entry"

        run_with_spinner "Downloading $name..." \
            bash -c 'download_binary "$@"' _ "$name" "$url" "$bin_dir/$name"

        if [[ $? -ne 0 ]]; then
            log_error "Failed to download $name."
            failed=1
        fi
    done

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "Binaries installed."
    return 0
}
