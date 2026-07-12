#!/bin/bash

# modules/desktop_entries.sh
#
# Deploy .desktop files and their icons from applications/ to the user's
# local XDG directories.
#
# Source layout (all under $REPO_ROOT/applications/):
#   *.desktop        → $HOME/.local/share/applications/
#   icons/<size>/*.png → $HOME/.local/share/icons/hicolor/<size>/apps/
#
# <size> is the subdirectory name (e.g. 128x128, 256x256) and maps directly
# to the XDG icon theme directory structure. Icon files are named after the
# application (e.g. ytdownloader.png) — matching the Icon= field in the
# corresponding .desktop file.
#
# To add a desktop entry:
#   1. Drop the .desktop file into applications/.
#   2. Drop its icon into applications/icons/<size>/<appname>.png.
#   That is all — no code changes needed.
#
# Icon install path is user-local on all three OSes (~/.local/share/icons/...).
# No sudo required. No OS branching.
#
# Reads:
#   REPO_ROOT — set by install.sh
#
# Public interface: run_desktop_entries()

# ------------------------------------------------------------------------------
# run_desktop_entries
# ------------------------------------------------------------------------------
run_desktop_entries() {
    local src_dir="$REPO_ROOT/applications"
    local desktop_dir="$HOME/.local/share/applications"
    local icon_base="$HOME/.local/share/icons/hicolor"

    if [[ ! -d "$src_dir" ]]; then
        log_error "applications/ source directory not found: $src_dir"
        return 1
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

    success_message "Desktop entries configured."
    return 0
}
