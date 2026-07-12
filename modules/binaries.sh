#!/bin/bash

# modules/binaries.sh
#
# Downloads binaries to $HOME/.local/bin. To add one, append a "name url"
# entry to _BINARIES.
#
# All downloads attempted regardless of individual failures; returns 1 if
# any failed. download_binary() (lib/utils.sh) skips silently if the binary
# already exists and is executable.
#
# Reads:
#   LOG_FILE — must be exported by install.sh; used by log_write in the
#              gum spin subprocess.
#
# Public interface: run_binaries()

_BINARIES=(
    "yt-dlp        https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
    "ytdownloader-linux  https://github.com/AswinGopal/ytdlp-gui/releases/latest/download/ytdownloader-linux"
)

# ------------------------------------------------------------------------------
# run_binaries
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
