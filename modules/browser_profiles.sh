#!/bin/bash

# modules/browser_profiles.sh
#
# Deploy browser profile desktop files and icons. This is the only module
# with internal OS_ID branching.
#
# Arch   — static copy. Icons installed system-wide (sudo).
# Fedora — static copy. Icons installed user-local (no sudo). gtk-update-icon-cache.
# Ubuntu — static copy. Wipes existing Firefox snap profile dir, creates three
#          fixed profiles (brave, chrome, edge), copies static .desktop files.
#
# Icons are shared across all distros — sourced from $REPO_ROOT/browser-profiles/*.png.
# OS-specific .desktop files are sourced from $REPO_ROOT/browser-profiles/$OS_ID/.
#
# Reads:
#   REPO_ROOT — set by install.sh
#   OS_ID     — set by install.sh (arch | fedora | ubuntu)
#
# Public interface: run_browser_profiles()

# ------------------------------------------------------------------------------
# _browser_profiles_arch
# ------------------------------------------------------------------------------
_browser_profiles_arch() {
    local src_dir="$REPO_ROOT/browser-profiles/arch"
    local icon_src="$REPO_ROOT/browser-profiles"
    local desktop_dir="$HOME/.local/share/applications"
    local icon_dir="/usr/share/icons/hicolor/256x256/apps"

    if [[ ! -d "$src_dir" ]]; then
        log_error "Browser profiles source not found: $src_dir"
        return 1
    fi

    mkdir -p "$desktop_dir"
    sudo mkdir -p "$icon_dir"

    local failed=0 file

    for file in "$src_dir/"*.desktop; do
        [[ -e "$file" ]] || continue
        cp "$file" "$desktop_dir/" || { log_error "Failed to copy $(basename "$file")"; failed=1; }
    done

    for file in "$icon_src/"*.png; do
        [[ -e "$file" ]] || continue
        sudo cp "$file" "$icon_dir/" || { log_error "Failed to copy $(basename "$file")"; failed=1; }
    done

    [[ $failed -ne 0 ]] && return 1

    success_message "Browser profiles configured."
    return 0
}

# ------------------------------------------------------------------------------
# _browser_profiles_fedora
# ------------------------------------------------------------------------------
_browser_profiles_fedora() {
    local src_dir="$REPO_ROOT/browser-profiles/fedora"
    local icon_src="$REPO_ROOT/browser-profiles"
    local desktop_dir="$HOME/.local/share/applications"
    local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"

    if [[ ! -d "$src_dir" ]]; then
        log_error "Browser profiles source not found: $src_dir"
        return 1
    fi

    mkdir -p "$desktop_dir" "$icon_dir"

    local failed=0 file

    for file in "$src_dir/"*.desktop; do
        [[ -e "$file" ]] || continue
        cp "$file" "$desktop_dir/" || { log_error "Failed to copy $(basename "$file")"; failed=1; }
    done

    for file in "$icon_src/"*.png; do
        [[ -e "$file" ]] || continue
        cp "$file" "$icon_dir/" || { log_error "Failed to copy $(basename "$file")"; failed=1; }
    done

    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1
    fi

    [[ $failed -ne 0 ]] && return 1

    success_message "Browser profiles configured."
    return 0
}

# ------------------------------------------------------------------------------
# _browser_profiles_ubuntu
#
# Wipe the existing Firefox snap profile directory entirely, create three fixed
# profiles (brave, chrome, edge), copy static .desktop files, and install icons.
#
# Profile deletion rationale: firefox -CreateProfile does not recreate
# *.default or *.default-release, so nuking the directory before creating
# profiles guarantees a clean three-profile state with no leftovers.
#
# Static .desktop files are pre-authored in browser-profiles/ubuntu/ 
# Icons are sourced from the browser-profiles/ root (shared across all distros).
# ------------------------------------------------------------------------------
_browser_profiles_ubuntu() {
    local src_dir="$REPO_ROOT/browser-profiles/ubuntu"
    local icon_src="$REPO_ROOT/browser-profiles"
    local firefox_profile_dir="$HOME/snap/firefox/common/.mozilla/firefox"
    local desktop_dir="$HOME/.local/share/applications"
    local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"

    local -a profiles=(brave chrome edge)

    if [[ ! -d "$src_dir" ]]; then
        log_error "Browser profiles source not found: $src_dir"
        return 1
    fi

    mkdir -p "$desktop_dir" "$icon_dir"

    # -- Wipe existing Firefox snap profile directory --------------------------
    # Removes *.default, *.default-release, and any prior profiles.ini so that
    # -CreateProfile starts from a clean slate.
    if [[ -d "$firefox_profile_dir" ]]; then
        rm -rf "$firefox_profile_dir" \
            || { log_error "Failed to remove existing Firefox profile directory."; return 1; }
    fi

    # -- Create fixed profiles -------------------------------------------------
    local profile failed=0
    for profile in "${profiles[@]}"; do
        if ! firefox -CreateProfile "$profile" >/dev/null 2>&1; then
            log_error "Failed to create Firefox profile: $profile"
            failed=1
        fi
    done

    [[ $failed -ne 0 ]] && return 1

    # -- Deploy .desktop files -------------------------------------------------
    local file
    for file in "$src_dir/"*.desktop; do
        [[ -e "$file" ]] || continue
        cp "$file" "$desktop_dir/" || { log_error "Failed to copy $(basename "$file")"; failed=1; }
    done

    # -- Install icons ---------------------------------------------------------
    for file in "$icon_src/"*.png; do
        [[ -e "$file" ]] || continue
        cp "$file" "$icon_dir/" || { log_error "Failed to copy $(basename "$file")"; failed=1; }
    done

    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1
    fi

    [[ $failed -ne 0 ]] && return 1

    success_message "Browser profiles configured."
    return 0
}

# ------------------------------------------------------------------------------
# run_browser_profiles
# ------------------------------------------------------------------------------
run_browser_profiles() {
    case "$OS_ID" in
        arch)   _browser_profiles_arch   ;;
        fedora) _browser_profiles_fedora ;;
        ubuntu) _browser_profiles_ubuntu ;;
        *)
            log_error "browser_profiles: unsupported OS_ID '$OS_ID'."
            return 1
            ;;
    esac
}
