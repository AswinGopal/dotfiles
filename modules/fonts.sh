#!/bin/bash

# modules/fonts.sh

# User-local install — no sudo required anywhere in this module. A font
# already present system-wide (e.g. from a prior sudo-based install, or a
# distro font package) is still detected and skipped via fc-list: anyone
# with root access to write a font into a system directory has by
# definition already had the ability to run sudo fc-cache -f, so the
# system-wide fontconfig cache is never stale on account of anything this
# module needs to account for. A plain, non-sudo fc-cache -f can read that
# cache — reading is unprivileged; only rebuilding a directory's cache
# requires ownership of it — so no sudo is needed here to detect it.
#
# To add a font: append its zip filename to the FONTS array. The font name
# is derived automatically by stripping the .zip suffix — no second array
# to keep in sync.
#
# Flow:
#   1. Create a private temp directory (cleaned up on any return via trap).
#   2. Run fc-cache -f once, before anything else, so the pre-pass below is
#      judged against accurate, current cache state.
#   3. Pre-pass: check every font in FONTS against fc-list. Fonts already
#      visible to fontconfig (user or system-wide) are skipped; anything
#      else is collected into a to-install list. No network call yet.
#   4. If nothing needs installing, stop here — the GitHub API is never
#      contacted when every font is already present.
#   5. Otherwise, fetch the latest release JSON from the GitHub API once —
#      shared across every font still in the to-install list.
#   6. For each font in the to-install list: resolve its URL from the JSON,
#      download (spinner), unzip, copy.
#   7. Run fc-cache -f once more, so newly installed fonts are live
#      immediately and next run's pre-pass stays accurate.
#
# Idempotent: a font already visible to fontconfig (user or system-wide) is
# skipped entirely — no API call, no download, no re-copy. The GitHub API is
# only contacted when at least one font actually needs installing.
#
# Reads:
#   LOG_FILE — must be exported by install.sh; used by log_write in the
#              gum spin subprocess.
#
# Public interface: run_fonts()

_FONT_INSTALL_PATH="$HOME/.local/share/fonts"
_NERD_FONTS_API="https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"

# Add fonts here — zip filenames only. Name is derived by stripping .zip.
_FONTS=(
    "Meslo.zip"
    "FiraCode.zip"
)

# ------------------------------------------------------------------------------
# _fonts_install font_file url tmp_dir
#
# Download, extract, and install one font. Called by run_fonts for each entry.
# Font name is derived from font_file via ${font_file%.zip}.
# curl is a binary so run_with_spinner wraps it directly — no export -f needed.
# ------------------------------------------------------------------------------
_fonts_install() {
    local font_file="$1"
    local url="$2"
    local tmp_dir="$3"
    local font_name="${font_file%.zip}"

    local zip_path="$tmp_dir/$font_file"
    local extract_path="$tmp_dir/$font_name"

    run_with_spinner "Downloading $font_name..." \
        curl -fsSL "$url" -o "$zip_path"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to download $font_name."
        return 1
    fi

    if ! unzip -q "$zip_path" -d "$extract_path"; then
        log_error "Failed to extract $font_name."
        return 1
    fi

    mkdir -p "$_FONT_INSTALL_PATH"

    if ! cp -r "$extract_path" "$_FONT_INSTALL_PATH/"; then
        log_error "Failed to install $font_name to $_FONT_INSTALL_PATH."
        return 1
    fi

    success_message "$font_name installed."
    return 0
}

# ------------------------------------------------------------------------------
# run_fonts
# ------------------------------------------------------------------------------
run_fonts() {
    local tmp_dir
    tmp_dir=$(mktemp -d) || { log_error "Failed to create temp directory."; return 1; }
    # $tmp_dir is expanded now (desired) so the correct path is captured in the trap.
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN

    # Establish accurate cache state before any skip checks run below —
    # correctness of those checks depends on this running first.
    if ! fc-cache -f; then
        log_error "Failed to refresh font cache."
        return 1
    fi

    # -- Pre-pass: determine which fonts actually need installing -------------
    # Done before any network call — a font already visible to fontconfig
    # (user or system-wide) has no reason to touch the GitHub API at all.
    local -a to_install=()
    local font_file
    for font_file in "${_FONTS[@]}"; do
        if ! fc-list | grep -qi "${font_file%.zip}"; then
            to_install+=("$font_file")
        fi
    done

    # Nothing to do — skip the API call entirely.
    if [[ ${#to_install[@]} -eq 0 ]]; then
        success_message "Fonts already installed."
        return 0
    fi

    # Fetch release JSON once — shared across every font that needs installing.
    local release_json
    release_json=$(curl -fsSL "$_NERD_FONTS_API") || {
        log_error "Failed to fetch nerd-fonts release info from GitHub API."
        return 1
    }

    local url
    for font_file in "${to_install[@]}"; do
        url=$(printf '%s' "$release_json" \
            | jq -r ".assets[] | select(.name == \"$font_file\") | .browser_download_url")

        if [[ -z "$url" ]]; then
            log_error "Could not resolve download URL for ${font_file%.zip}."
            return 1
        fi

        _fonts_install "$font_file" "$url" "$tmp_dir" || return 1
    done

    if ! fc-cache -f; then
        log_error "Failed to update font cache."
        return 1
    fi

    success_message "Fonts installed."
    return 0
}
