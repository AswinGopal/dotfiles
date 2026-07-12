#!/bin/bash

# modules/secure_boot.sh
#
# Arch only. Install Secure Boot signing scripts and pacman hooks.
# Off by default in os/arch.sh MODULES — must be explicitly selected.
#
# Files deployed:
#   kernel-sbsign              → /etc/initcpio/post/  (executable)
#   80-secureboot.hook         → /etc/pacman.d/hooks/
#   remove-fallback-bootx64.hook → /etc/pacman.d/hooks/
#
# DESTRUCTIVE: writes to boot-critical system paths. A gum_confirm gate fires
# before any write. Declining is not a failure — the module returns 0 and
# records the skip. All source files are validated before any system path
# is touched to prevent partial installation.
#
# Idempotent: sudo cp overwrites, sudo chmod +x on an already-executable
# file is a no-op. Safe to re-run.
#
# Reads:
#   REPO_ROOT — set by install.sh
#
# Public interface: run_secure_boot()

# ------------------------------------------------------------------------------
# run_secure_boot
# ------------------------------------------------------------------------------
run_secure_boot() {
    local src_dir="$REPO_ROOT/SB-sign-scripts"

    if [[ ! -d "$src_dir" ]]; then
        log_error "SB-sign-scripts source not found: $src_dir"
        return 1
    fi

    # Validate all source files exist before touching any system path.
    local -a required_files=(
        "kernel-sbsign"
        "80-secureboot.hook"
        "remove-fallback-bootx64.hook"
    )

    local f
    for f in "${required_files[@]}"; do
        if [[ ! -f "$src_dir/$f" ]]; then
            log_error "Required file not found: $src_dir/$f"
            return 1
        fi
    done

    # Gate: all writes to boot-critical system paths require explicit confirmation.
    # Declining is a valid outcome — return 0, not 1.
    if ! gum_confirm "Install Secure Boot signing scripts to /etc/initcpio/post and /etc/pacman.d/hooks? This modifies boot-critical system paths."; then
        show_info "Secure Boot setup skipped."
        return 0
    fi

    # -- Target directories ----------------------------------------------------
    sudo mkdir -p /etc/initcpio/post \
        || { log_error "Failed to create /etc/initcpio/post"; return 1; }

    sudo mkdir -p /etc/pacman.d/hooks \
        || { log_error "Failed to create /etc/pacman.d/hooks"; return 1; }

    # -- kernel-sbsign → /etc/initcpio/post/ -----------------------------------
    sudo cp "$src_dir/kernel-sbsign" /etc/initcpio/post/ \
        || { log_error "Failed to copy kernel-sbsign"; return 1; }

    sudo chmod +x /etc/initcpio/post/kernel-sbsign \
        || { log_error "Failed to make kernel-sbsign executable"; return 1; }

    # -- pacman hooks → /etc/pacman.d/hooks/ -----------------------------------
    sudo cp "$src_dir/80-secureboot.hook" /etc/pacman.d/hooks/ \
        || { log_error "Failed to copy 80-secureboot.hook"; return 1; }

    # Copies remove-fallback-bootx64.hook to prevent UEFI from creating
    # fallback boot entries via BOOTX64.efi on the ESP.
    sudo cp "$src_dir/remove-fallback-bootx64.hook" /etc/pacman.d/hooks/ \
        || { log_error "Failed to copy remove-fallback-bootx64.hook"; return 1; }

    success_message "Secure Boot scripts installed."
    return 0
}
