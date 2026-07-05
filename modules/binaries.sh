#!/bin/bash

# modules/binaries.sh
#
# Download yt-dlp, git_info, and ytdownloader to $HOME/.local/bin.
#
# yt-dlp        — critical; the mpv module depends on it. Module fails if this fails.
# git_info      — best-effort; failure is logged but does not fail the module.
# ytdownloader  — best-effort; failure is logged but does not fail the module.
#
# Idempotency is provided by download_binary() in lib/utils.sh — each binary
# is skipped silently if it already exists and is executable.
#
# Reads:
#   LOG_FILE — must be exported by install.sh; used by log_write in the
#              gum spin subprocess.
#
# Public interface: run_binaries()

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

    # -- yt-dlp (critical) -----------------------------------------------------
    run_with_spinner "Downloading yt-dlp..." \
        bash -c 'download_binary "$@"' _ \
        "yt-dlp" \
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
        "$bin_dir/yt-dlp"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to download yt-dlp."
        return 1
    fi

    # -- git_info (best-effort) ------------------------------------------------
    run_with_spinner "Downloading git_info..." \
        bash -c 'download_binary "$@"' _ \
        "git_info" \
        "https://github.com/AswinGopal/git_info/releases/latest/download/git_info" \
        "$bin_dir/git_info"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to download git_info."
    fi

    # -- ytdownloader (best-effort) --------------------------------------------
    run_with_spinner "Downloading ytdownloader..." \
        bash -c 'download_binary "$@"' _ \
        "ytdownloader" \
        "https://github.com/AswinGopal/ytdownloader/releases/latest/download/ytdownloader" \
        "$bin_dir/ytdownloader"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to download ytdownloader."
    fi

    success_message "Binaries installed."
    return 0
}
