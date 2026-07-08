#!/bin/bash

# modules/browser_profiles.sh
#
# Deploy browser profile desktop files and icons.
#
# All three OSes: wipe existing Firefox profile directory, create three fixed
# profiles (brave, chrome, edge), copy static .desktop files, install icons,
# deploy per-profile user.js overrides.
#
# The only per-OS difference is the Firefox profile directory path:
#   Arch   — $HOME/.mozilla/firefox
#   Fedora — $HOME/.config/mozilla/firefox
#   Ubuntu — $HOME/snap/firefox/common/.mozilla/firefox
#
# Icons are shared across all distros — sourced from $REPO_ROOT/browser-profiles/*.png.
# OS-specific .desktop files are sourced from $REPO_ROOT/browser-profiles/$OS_ID/.
# Icons installed user-local on all three OSes. No sudo required.
#
# Per-profile user.js overrides — mapping is OS-independent (profile_js below),
# sourced from $REPO_ROOT/browser-profiles/*.js. Firefox only reads a file named
# exactly "user.js" inside a profile's own versioned directory, so the source
# filename is renamed on copy. A profile with no entry in the map (chrome) is
# left with Firefox's default prefs. The versioned profile directory name is
# not known until firefox -CreateProfile has run, so resolution happens inside
# the same loop, immediately after each profile is created.
#
# Reads:
#   REPO_ROOT — set by install.sh
#   OS_ID     — set by install.sh (arch | fedora | ubuntu)
#
# Public interface: run_browser_profiles()

# ------------------------------------------------------------------------------
# run_browser_profiles
# ------------------------------------------------------------------------------
run_browser_profiles() {
    local src_dir="$REPO_ROOT/browser-profiles/$OS_ID"
    local icon_src="$REPO_ROOT/browser-profiles"
    local desktop_dir="$HOME/.local/share/applications"
    local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"

    local firefox_profile_dir
    case "$OS_ID" in
        arch)   firefox_profile_dir="$HOME/.mozilla/firefox" ;;
        fedora) firefox_profile_dir="$HOME/.config/mozilla/firefox" ;;
        ubuntu) firefox_profile_dir="$HOME/snap/firefox/common/.mozilla/firefox" ;;
        *)
            log_error "browser_profiles: unsupported OS_ID '$OS_ID'."
            return 1
            ;;
    esac

    local -a profiles=(brave chrome edge)

    # Profile → user.js source filename. No entry means no override deployed
    # (chrome keeps Firefox defaults).
    local -A profile_js=(
        [brave]="user-overrides.js"
        [edge]="user-overrides-erase_all.js"
    )

    if [[ ! -d "$src_dir" ]]; then
        log_error "Browser profiles source not found: $src_dir"
        return 1
    fi

    mkdir -p "$desktop_dir" "$icon_dir"

    # -- Wipe existing Firefox profile directory --------------------------------
    # Guarantees a clean three-profile state with no leftover default profiles.
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
            continue
        fi

        # -- Deploy user.js override, if this profile has one -------------------
        # Skipped entirely for profiles absent from profile_js (e.g. chrome).
        if [[ -n "${profile_js[$profile]:-}" ]]; then
            local profile_path
            profile_path=$(find "$firefox_profile_dir" -maxdepth 1 -type d -name "*.$profile" | head -1)

            if [[ -z "$profile_path" ]]; then
                log_error "Could not resolve profile directory for: $profile"
                failed=1
            elif ! cp "$icon_src/${profile_js[$profile]}" "$profile_path/user.js"; then
                log_error "Failed to copy user.js for profile: $profile"
                failed=1
            fi
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