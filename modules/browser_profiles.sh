#!/bin/bash

# modules/browser_profiles.sh
#
# Deploy browser profile desktop files and icons. This is the only module
# with internal OS_ID branching.
#
# Arch   — static copy. Icons installed system-wide (sudo).
# Fedora — static copy. Icons installed user-local (no sudo). gtk-update-icon-cache.
# Ubuntu — interactive Firefox snap profile creation via gum_input/gum_confirm.
#          Icons installed user-local. Per-profile desktop shortcuts generated.
#
# Source: $REPO_ROOT/browser-profiles/$OS_ID/
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

    for file in "$src_dir/"*.png; do
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

    for file in "$src_dir/"*.png; do
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
# Interactive Firefox snap profile setup. Collects profile names via gum_input,
# creates each profile, optionally installs user.js (Betterfox) + user-overrides.js,
# and generates a per-profile desktop shortcut.
#
# user.js is downloaded once and cached in a temp dir for the duration of this
# function, then cleaned up via trap RETURN.
# ------------------------------------------------------------------------------
_browser_profiles_ubuntu() {
    local src_dir="$REPO_ROOT/browser-profiles/ubuntu"
    local firefox_profile_dir="$HOME/snap/firefox/common/.mozilla/firefox"
    local desktop_dir="$HOME/.local/share/applications"
    local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
    local snap_desktop="/var/lib/snapd/desktop/applications/firefox_firefox.desktop"
    local userjs_url="https://raw.githubusercontent.com/yokoffing/Betterfox/main/user.js"

    if [[ ! -d "$src_dir" ]]; then
        log_error "Browser profiles source not found: $src_dir"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d) || { log_error "Failed to create temp directory."; return 1; }
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN

    mkdir -p "$desktop_dir" "$icon_dir"

    # -- Install icons ---------------------------------------------------------
    local file
    for file in "$src_dir/"*.png; do
        [[ -e "$file" ]] || continue
        cp "$file" "$icon_dir/" || log_error "Failed to copy $(basename "$file")"
    done

    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1
    fi

    # -- Collect Firefox profile names via gum_input ---------------------------
    local -a profiles=()
    local name
    while true; do
        name=$(gum_input "Firefox profile name (empty to finish)")
        [[ $? -ne 0 || -z "$name" ]] && break
        profiles+=("$name")
    done

    # No profiles requested — icons were still installed, that is a valid outcome.
    if [[ ${#profiles[@]} -eq 0 ]]; then
        success_message "Browser profiles configured (icons only)."
        return 0
    fi

    if [[ ! -f "$snap_desktop" ]]; then
        log_error "Firefox snap desktop template not found: $snap_desktop"
        return 1
    fi

    local userjs_tmp="$tmp_dir/user.js"
    local userjs_downloaded=false

    for profile in "${profiles[@]}"; do

        # -- Idempotency: locate existing profile dir before creating ----------
        local profile_dir
        profile_dir=$(find "$firefox_profile_dir" -maxdepth 1 \
            -type d -name "*.$profile" -exec basename {} \; 2>/dev/null | head -1)

        if [[ -z "$profile_dir" ]]; then
            run_with_spinner "Creating Firefox profile '$profile'..." \
                firefox -CreateProfile "$profile"

            if [[ $? -ne 0 ]]; then
                log_error "Failed to create Firefox profile: $profile"
                continue
            fi

            profile_dir=$(find "$firefox_profile_dir" -maxdepth 1 \
                -type d -name "*.$profile" -exec basename {} \; 2>/dev/null | head -1)

            if [[ -z "$profile_dir" ]]; then
                log_error "Could not locate profile directory for: $profile"
                continue
            fi
        fi

        # -- Optionally install user.js (Betterfox) ----------------------------
        if gum_confirm "Add user.js (Betterfox) to profile '$profile'?"; then

            if [[ "$userjs_downloaded" == false ]]; then
                run_with_spinner "Downloading user.js..." \
                    curl -fsSL "$userjs_url" -o "$userjs_tmp"

                if [[ $? -ne 0 ]]; then
                    log_error "Failed to download user.js — skipping for profile: $profile"
                else
                    userjs_downloaded=true
                fi
            fi

            if [[ "$userjs_downloaded" == true ]]; then
                cp "$userjs_tmp" "$firefox_profile_dir/$profile_dir/user.js" \
                    || log_error "Failed to install user.js to profile: $profile"

                local overrides_choice
                overrides_choice=$("$GUM" choose \
                    --header="Select user-overrides for profile '$profile'" \
                    "user-overrides.js" \
                    "user-overrides-erase_all.js" \
                    "Skip")

                case "$overrides_choice" in
                    "user-overrides.js"|"user-overrides-erase_all.js")
                        local overrides_src="$REPO_ROOT/browser-profiles/$overrides_choice"
                        if [[ -f "$overrides_src" ]]; then
                            cp "$overrides_src" "$firefox_profile_dir/$profile_dir/" \
                                || log_error "Failed to copy $overrides_choice to profile: $profile"
                        else
                            log_error "user-overrides file not found: $overrides_src"
                        fi
                        ;;
                    *)
                        # "Skip" or Ctrl-C / empty — no overrides installed for this profile
                        ;;
                esac
            fi
        fi

        # -- Create per-profile desktop shortcut -------------------------------
        local desktop_file="$desktop_dir/firefox_${profile}.desktop"

        if ! cp "$snap_desktop" "$desktop_file"; then
            log_error "Failed to create desktop file for profile: $profile"
            continue
        fi

        # Capitalize first letter of profile name for display
        local display_name
        display_name=$(printf '%s' "$profile" | sed 's/.*/\L\u&/')

        # Escape characters special in a sed replacement string (&, |, \) so
        # user-supplied profile names cannot corrupt the substitutions below.
        local safe_profile safe_display_name
        safe_profile=$(printf '%s' "$profile" | sed 's/[&|\\]/\\&/g')
        safe_display_name=$(printf '%s' "$display_name" | sed 's/[&|\\]/\\&/g')

        sed -i "s|/snap/bin/firefox -new-window|& -p $safe_profile|g"         "$desktop_file"
        sed -i "s|/snap/bin/firefox -private-window|& -p $safe_profile|g"     "$desktop_file"
        sed -i "s|\(/snap/bin/firefox\) %u$|\1 -p $safe_profile %u|g"         "$desktop_file"
        sed -i "s|Name=Firefox Web Browser|Name=$safe_display_name Browser|g" "$desktop_file"

    done

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
