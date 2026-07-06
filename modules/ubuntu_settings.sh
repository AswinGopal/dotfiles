#!/bin/bash

# modules/ubuntu_settings.sh
#
# Ubuntu only. Apply GNOME and system settings via gsettings and timedatectl.
#
# All settings are independent — a failure in one does not block the others.
# The module returns 1 if any setting failed, 0 if all succeeded.
#
# Idempotent: gsettings set and timedatectl are no-ops if the value is already
# set. Safe to re-run.
#
# No spinner — all operations are local system calls (milliseconds).
#
# To add a setting: add an explicit if-block following the pattern below.
# To disable a setting: comment out its block.
#
# Public interface: run_ubuntu_settings()

# ------------------------------------------------------------------------------
# run_ubuntu_settings
# ------------------------------------------------------------------------------
run_ubuntu_settings() {
    local failed=0

    # Window close shortcut: Super+W
    if ! gsettings set org.gnome.desktop.wm.keybindings close "['<Super>w']"; then
        log_error "Failed to set window close shortcut."
        failed=1
    fi

    # Screen blank: never
    if ! gsettings set org.gnome.desktop.session idle-delay 0; then
        log_error "Failed to disable screen blank."
        failed=1
    fi

    # System timezone
    if ! sudo timedatectl set-timezone Asia/Kolkata; then
        log_error "Failed to set timezone."
        failed=1
    fi

    # 12-hour clock — GNOME shell
    if ! gsettings set org.gnome.desktop.interface clock-format '12h'; then
        log_error "Failed to set GNOME clock format."
        failed=1
    fi

    # 12-hour clock — GTK file chooser
    if ! gsettings set org.gtk.Settings.FileChooser clock-format '12h'; then
        log_error "Failed to set GTK file chooser clock format."
        failed=1
    fi

    # Hardware clock to local time (dual-boot Windows compatibility)
    if ! sudo timedatectl set-local-rtc 1; then
        log_error "Failed to set hardware clock to local time."
        failed=1
    fi

    # Terminal key shortcut: Super+Return (disabled — conflicts with some setups)
    # gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "['<Super>Return']"

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "GNOME settings applied."
    return 0
}
