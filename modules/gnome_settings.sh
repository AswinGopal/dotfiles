#!/bin/bash

# modules/gnome_settings.sh
#
# GNOME Shell / GSettings configuration. Not distro-specific — targets the
# GNOME desktop environment itself, wherever it is running (Ubuntu, Fedora,
# or Arch with GNOME installed). Superseded the old ubuntu_settings.sh:
# every key this module touches (org.gnome.*, org.gtk.Settings.FileChooser)
# is GNOME/GTK state, not Ubuntu-the-distro state.
#
# GATE: run_gnome_settings() checks is_gnome_session() first and returns 0
# (correct no-op, not a failure) if the current session is not GNOME. This
# is what makes the module safe to list as on-by-default on Arch, where a
# GNOME desktop is never guaranteed.
#
# IDEMPOTENCY: every write in this module goes through
# gsettings_set_if_changed / timedatectl_set_timezone_if_changed (both in
# lib/utils.sh) rather than a raw `gsettings set` / `timedatectl
# set-timezone`. A raw `gsettings set` fires a change-notify signal even
# when the value is unchanged, which can cause visible side effects (redraw
# / flicker) on an already-configured system re-running this module — the
# check-first helpers avoid that on repeat runs.
#
# All settings are independent — a failure in one does not block the
# others. The module returns 1 if any setting failed, 0 if all succeeded
# (including the case where every value was already correct and nothing
# was written).
#
# To add a setting: add an explicit block following the pattern below.
# To disable a setting: comment out its block.
#
# Public interface: run_gnome_settings()

# ------------------------------------------------------------------------------
# run_gnome_settings
# ------------------------------------------------------------------------------
run_gnome_settings() {
    if ! is_gnome_session; then
        show_info "Current session is not GNOME — skipping GNOME settings."
        return 0
    fi

    local failed=0

    # -- Window close shortcut: Super+W -----------------------------------------
    gsettings_set_if_changed org.gnome.desktop.wm.keybindings close "['<Super>w']" \
        || { log_error "Failed to set window close shortcut."; failed=1; }

    # -- Screen blank: never -----------------------------------------------------
    gsettings_set_if_changed org.gnome.desktop.session idle-delay "uint32 0" \
        || { log_error "Failed to disable screen blank."; failed=1; }

    # -- 12-hour clock — GNOME shell ---------------------------------------------
    gsettings_set_if_changed org.gnome.desktop.interface clock-format "'12h'" \
        || { log_error "Failed to set GNOME clock format."; failed=1; }

    # -- 12-hour clock — GTK file chooser ----------------------------------------
    gsettings_set_if_changed org.gtk.Settings.FileChooser clock-format "'12h'" \
        || { log_error "Failed to set GTK file chooser clock format."; failed=1; }

    # -- System timezone ----------------------------------------------------------
    timedatectl_set_timezone_if_changed "Asia/Kolkata" \
        || { log_error "Failed to set timezone."; failed=1; }

    # -- Terminal shortcut: Super+Return → Ptyxis (custom keybinding) -----------
    # GNOME no longer exposes a built-in "default terminal" media-key
    # (org.gnome.settings-daemon.plugins.media-keys terminal is gone post-
    # rewrite); Ptyxis must be registered as a custom keybinding instead.
    # Schema/path/key values confirmed against a live GNOME instance.
    #
    # Treated as one atomic logical setting, not five independent ones: a
    # partial write (e.g. the array registered but "binding" missing) is a
    # broken, non-functional shortcut either way, so a single failure point
    # is more honest than five separate pass/fail entries for what is
    # functionally one setting. Each individual key is still idempotent via
    # gsettings_set_if_changed — a key that already matches is a no-op even
    # within this grouped block.
    local terminal_keybind_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
    local terminal_keybind_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$terminal_keybind_path"
    if ! { gsettings_set_if_changed org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
                "['$terminal_keybind_path']" \
            && gsettings_set_if_changed "$terminal_keybind_schema" name "'terminal'" \
            && gsettings_set_if_changed "$terminal_keybind_schema" command "'ptyxis'" \
            && gsettings_set_if_changed "$terminal_keybind_schema" binding "'<Super>Return'" \
            && gsettings_set_if_changed "$terminal_keybind_schema" enable-in-lockscreen "false"; }; then
        log_error "Failed to set terminal shortcut."
        failed=1
    fi

    # -- Mouse acceleration: off (flat profile) ----------------------------------
    gsettings_set_if_changed org.gnome.desktop.peripherals.mouse accel-profile "'flat'" \
        || { log_error "Failed to disable mouse acceleration."; failed=1; }

    # -- Automatic suspend: off on AC power (battery left at default) -----------
    # Confirmed via fresh-install vs configured-machine diff: stock default is
    # 'suspend' on both AC and battery; only AC is overridden here, battery
    # intentionally left untouched.
    gsettings_set_if_changed org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'" \
        || { log_error "Failed to disable automatic suspend on AC power."; failed=1; }

    # -- Privacy: don't remember recent files ------------------------------------
    gsettings_set_if_changed org.gnome.desktop.privacy remember-recent-files "false" \
        || { log_error "Failed to disable recent files history."; failed=1; }


    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "GNOME settings applied."
    return 0
}
