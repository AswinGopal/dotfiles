#!/bin/bash

# modules/fonts.sh
#
# Download and install Meslo and FiraCode Nerd Fonts from the latest
# ryanoasis/nerd-fonts GitHub release into /usr/local/share/fonts/.
#
# To add a font: append its zip filename to the FONTS array. The font name
# is derived automatically by stripping the .zip suffix — no second array
# to keep in sync.
#
# Flow:
#   1. Create a private temp directory (cleaned up on any return via trap).
#   2. Fetch the latest release JSON from the GitHub API once.
#   3. For each font: resolve URL from JSON, download (spinner), unzip, copy.
#   4. Run sudo fc-cache -f once after all fonts are installed.
#
# Idempotent: re-running re-downloads and re-copies. Result is identical.
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

    sudo mkdir -p "$_FONT_INSTALL_PATH"

    if ! sudo cp -r "$extract_path" "$_FONT_INSTALL_PATH/"; then
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

    # Fetch release JSON once — all fonts resolve their URLs from this payload.
    local release_json
    release_json=$(curl -fsSL "$_NERD_FONTS_API") || {
        log_error "Failed to fetch nerd-fonts release info from GitHub API."
        return 1
    }

    local font_file url
    for font_file in "${_FONTS[@]}"; do
        url=$(printf '%s' "$release_json" \
            | jq -r ".assets[] | select(.name == \"$font_file\") | .browser_download_url")

        if [[ -z "$url" ]]; then
            log_error "Could not resolve download URL for ${font_file%.zip}."
            return 1
        fi

        _fonts_install "$font_file" "$url" "$tmp_dir" || return 1
    done

    if ! sudo fc-cache -f; then
        log_error "Failed to update font cache."
        return 1
    fi

    success_message "Fonts installed."
    return 0
}
