#!/bin/bash
#
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
# Per-profile user.js override files — mapping is OS-independent (profile_js
# below), sourced from $REPO_ROOT/browser-profiles/*.js and copied as-is (no
# rename) into the profile's own versioned directory. A profile with no entry
# in the map (chrome) gets no override file. The versioned profile directory
# name is not known until firefox -CreateProfile has run, so resolution
# happens inside the same loop, immediately after each profile is created.
#
# FRESH-INSTALL PRECONDITION:
# This module exists to set up profiles on a fresh Firefox install, not to
# reconcile an already-customized one. Before wiping anything, it inspects
# profiles.ini (if present) in the target Firefox profile directory:
#   - profiles.ini absent           → treated as fresh; wipe proceeds.
#   - profiles.ini has exactly the
#     stock {default, default-release} profiles and nothing else
#                                    → treated as fresh; wipe proceeds.
#   - anything else (either stock profile missing, or any additional
#     profile present, e.g. user-created or from a prior run)
#                                    → treated as already customized by the
#                                      user; the module does nothing and
#                                      returns 0.
#
# Reads:
#   REPO_ROOT — set by install.sh
#   OS_ID     — set by install.sh (arch | fedora | ubuntu)
#
# Public interface: run_browser_profiles()


# ------------------------------------------------------------------------------
# _firefox_profiles_are_stock profiles_ini_path
#
# Determine whether a profiles.ini describes exactly the untouched, stock
# Firefox state: a "default" profile and a "default-release" profile, and
# nothing else.
#
# profiles.ini is a flat INI file with repeated, non-fixed-order sections —
# [ProfileN] (N in any order), [General], and [InstallHASH...]. Only the
# Name= line inside a [ProfileN] section identifies a profile. [InstallHASH]
# sections also contain a Default= line, but it holds a profile *path*, not
# a name, and must not be confused with the Default=1 flag that can appear
# inside a [ProfileN] section. A plain grep for Name= or Default= across the
# whole file cannot distinguish these cases reliably — this function tracks
# which section it is currently inside and only collects Name= while inside
# a [ProfileN] section.
#
# Returns: 0 if the profile set is exactly {default, default-release}.
#          1 otherwise (including a missing or empty file).
# ------------------------------------------------------------------------------
_firefox_profiles_are_stock() {
    local ini_path="$1"

    [[ -f "$ini_path" ]] || return 1

    local in_profile_section=0
    local line name
    local -a found_names=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\[Profile[0-9]+\]$ ]]; then
            in_profile_section=1
            continue
        elif [[ "$line" =~ ^\[.*\]$ ]]; then
            in_profile_section=0
            continue
        fi

        if [[ $in_profile_section -eq 1 && "$line" =~ ^Name=(.*)$ ]]; then
            found_names+=("${BASH_REMATCH[1]}")
        fi
    done < "$ini_path"

    # Exactly two profiles, and they are default and default-release —
    # order independent, no extras, none missing.
    [[ ${#found_names[@]} -eq 2 ]] || return 1

    local has_default=0 has_default_release=0
    for name in "${found_names[@]}"; do
        case "$name" in
            default)         has_default=1 ;;
            default-release) has_default_release=1 ;;
            *)                return 1 ;;
        esac
    done

    [[ $has_default -eq 1 && $has_default_release -eq 1 ]] || return 1
    return 0
}

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
    local -A profile_js=(
        [brave]="user-overrides.js"
        [edge]="user-overrides-erase_all.js"
    )

    if [[ ! -d "$src_dir" ]]; then
        log_error "Browser profiles source not found: $src_dir"
        return 1
    fi

    # -- Fresh-install precondition check ---------------------------------------
    local profiles_ini="$firefox_profile_dir/profiles.ini"
    if [[ -f "$profiles_ini" ]] && ! _firefox_profiles_are_stock "$profiles_ini"; then
        show_info "Existing customized Firefox profiles detected — skipping browser profile setup."
        return 0
    fi

    mkdir -p "$desktop_dir" "$icon_dir"

    # -- Wipe existing Firefox profile directory --------------------------------
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
            elif ! cp "$icon_src/${profile_js[$profile]}" "$profile_path/"; then
                log_error "Failed to copy ${profile_js[$profile]} for profile: $profile"
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

    # -- Refresh desktop file / MIME association cache --------------------------
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$desktop_dir" >/dev/null 2>&1
    fi

    [[ $failed -ne 0 ]] && return 1

    success_message "Browser profiles configured."
    return 0
}