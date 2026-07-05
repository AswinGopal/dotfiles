#!/bin/bash

# modules/mpv.sh
#
# Deploy the shared mpv config to $HOME/.config/mpv and substitute the
# __YT_DLP_PATH__ placeholder in mpv.conf with the actual yt-dlp binary path.
#
# Source: $REPO_ROOT/mpv/  (single shared dir — identical across all distros)
# Dest:   $HOME/.config/mpv/
#
# Idempotent: cp restores files from source on every run (including the
# placeholder), then sed re-substitutes. Safe to re-run.
#
# Reads:
#   REPO_ROOT — set by install.sh
#
# Public interface: run_mpv()

# ------------------------------------------------------------------------------
# run_mpv
# ------------------------------------------------------------------------------
run_mpv() {
    local src_dir="$REPO_ROOT/mpv"
    local dest_dir="$HOME/.config/mpv"
    local yt_dlp_path="$HOME/.local/bin/yt-dlp"

    if [[ ! -d "$src_dir" ]]; then
        log_error "mpv config source not found: $src_dir"
        return 1
    fi

    mkdir -p "$dest_dir" || { log_error "Failed to create $dest_dir"; return 1; }

    if ! cp "$src_dir/"* "$dest_dir/"; then
        log_error "Failed to copy mpv config to $dest_dir"
        return 1
    fi

    if ! sed -i "s|__YT_DLP_PATH__|$yt_dlp_path|g" "$dest_dir/mpv.conf"; then
        log_error "Failed to substitute yt-dlp path in mpv.conf"
        return 1
    fi

    success_message "mpv configured."
    return 0
}
