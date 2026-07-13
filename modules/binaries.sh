#!/bin/bash

# modules/binaries.sh
#
# Downloads binaries to $HOME/.local/bin. To add one, append a "name url"
# entry to _BINARIES.
#
# All downloads attempted regardless of individual failures; failures are
# logged and looping continues. download_binary() (lib/utils.sh) skips
# silently if the binary already exists and is executable.
#
# Also owns deployment of $REPO_ROOT/applications/ — desktop entries and
# icons for any binary in _BINARIES that ships a GUI launcher (e.g.
# ytdownloader-linux → applications/ytdownloader.desktop). applications/
# exists solely to serve binaries downloaded by this module; there is no
# desktop entry in this repo that is not tied to an entry in _BINARIES.
# The download-artifact name (e.g. ytdownloader-linux, dictated by upstream
# release-asset naming) and the desktop-entry/icon name (e.g. ytdownloader,
# dictated by desktop-integration convention) are not expected to match, so
# deployment is a directory sweep of all of applications/, not a per-binary
# name lookup — a binary with no matching desktop entry (e.g. yt-dlp) is
# simply unaffected by the sweep.
#
# The sweep only runs if every download in the loop above it succeeded.
# This is a deliberate exception to the "log and continue independently"
# rule the rest of this module follows: a deployed .desktop file whose
# Exec= target failed to download is a launcher that is worse than none —
# it appears to work and then fails silently when clicked. A sweep failure
# (copy or icon-cache error) also fails the module, for the same reason in
# reverse — do not report success while a launcher may be missing its icon.
#
# Reads:
#   REPO_ROOT — set by install.sh; used to locate applications/ for the sweep.
#   LOG_FILE  — must be exported by install.sh; used by log_write in the
#               gum spin subprocess.
#
# Public interface: run_binaries()

_BINARIES=(
    "yt-dlp        https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
    "ytdownloader-linux  https://github.com/AswinGopal/ytdlp-gui/releases/latest/download/ytdownloader-linux"
)

# ------------------------------------------------------------------------------
# _deploy_desktop_entries
#
# Deploy every .desktop file and icon under $REPO_ROOT/applications/ to the
# user's local XDG directories. Private to this module — called only by
# run_binaries, and only after every download in _BINARIES has succeeded.
#
# Source layout (all under $REPO_ROOT/applications/):
#   *.desktop          → $HOME/.local/share/applications/
#   icons/<size>/*.png → $HOME/.local/share/icons/hicolor/<size>/apps/
#
# <size> is the subdirectory name (e.g. 128x128, 256x256) and maps directly
# to the XDG icon theme directory structure. Icon files are named after the
# application (e.g. ytdownloader.png) — matching the Icon= field in the
# corresponding .desktop file.
#
# To add a desktop entry for a binary:
#   1. Add the binary to _BINARIES.
#   2. Drop its .desktop file into applications/.
#   3. Drop its icon into applications/icons/<size>/<appname>.png.
#   That is all — no further code changes needed.
#
# Icon install path is user-local on all three OSes (~/.local/share/icons/...).
# No sudo required. No OS branching.
#
# A missing applications/ directory is not an error — not every checkout of
# this repo is guaranteed to have GUI-launcher binaries defined.
#
# Returns: 0 on success, 1 if any copy or directory-creation step failed.
# ------------------------------------------------------------------------------
_deploy_desktop_entries() {
    local src_dir="$REPO_ROOT/applications"
    local desktop_dir="$HOME/.local/share/applications"
    local icon_base="$HOME/.local/share/icons/hicolor"

    if [[ ! -d "$src_dir" ]]; then
        return 0
    fi

    mkdir -p "$desktop_dir" || { log_error "Failed to create $desktop_dir"; return 1; }

    # -- Deploy .desktop files -------------------------------------------------
    local failed=0 file

    for file in "$src_dir/"*.desktop; do
        [[ -e "$file" ]] || continue
        cp "$file" "$desktop_dir/" || {
            log_error "Failed to copy $(basename "$file") to $desktop_dir"
            failed=1
        }
    done

    # -- Deploy icons ----------------------------------------------------------
    # Each subdirectory of applications/icons/ is a size bucket (e.g. 128x128).
    # Every .png inside maps to hicolor/<size>/apps/<appname>.png.
    # Size is derived from the directory name — no hardcoding.
    local size_dir size icon_dir icon_file

    for size_dir in "$src_dir/icons/"/*/; do
        [[ -d "$size_dir" ]] || continue

        size=$(basename "$size_dir")
        icon_dir="$icon_base/$size/apps"

        mkdir -p "$icon_dir" || {
            log_error "Failed to create icon directory: $icon_dir"
            failed=1
            continue
        }

        for icon_file in "$size_dir"*.png; do
            [[ -e "$icon_file" ]] || continue
            cp "$icon_file" "$icon_dir/" || {
                log_error "Failed to copy $(basename "$icon_file") to $icon_dir"
                failed=1
            }
        done
    done

    # -- Refresh icon cache ----------------------------------------------------
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t "$icon_base" >/dev/null 2>&1
    fi

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    return 0
}

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

    # -- Desktop entries ---------------------------------------------------
    # Only deploy if every download above succeeded — a .desktop file for a
    # binary that failed to download would be a launcher that fails when
    # clicked, which is worse than no launcher at all.
    if [[ $failed -eq 0 ]]; then
        if ! _deploy_desktop_entries; then
            log_error "Failed to deploy desktop entries."
            failed=1
        fi
    fi

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "Binaries installed."
    return 0
}
