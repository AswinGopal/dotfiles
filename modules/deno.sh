#!/bin/bash

# modules/deno.sh
#
# Download and install the Deno JavaScript runtime to ~/.deno/bin/deno.
#
# Install path mirrors the official installer convention ($DENO_INSTALL/bin/deno)
# so any tooling or documentation referencing $DENO_INSTALL remains compatible.
#
# Flow:
#   1. Idempotency check — skip silently if ~/.deno/bin/deno already exists
#      and is executable.
#   2. Detect architecture (x86_64 or aarch64).
#   3. Fetch latest version string from dl.deno.land.
#   4. Download zip to a private temp dir (cleaned up via trap RETURN).
#   5. Extract binary to ~/.deno/bin/, chmod +x.
#   6. Run official shell setup non-interactively (-y) — creates ~/.deno/env,
#      generates bash completions, and appends both source lines to ~/.bashrc.
#
# PATH note: the bash module must run before this module. The shell setup step
# appends to ~/.bashrc directly; if deno runs first, those additions are
# overwritten when bash deploys its dotfiles. Enforced by MODULES order in
# os/<distro>.sh.
#
# Public interface: run_deno()

# ------------------------------------------------------------------------------
# run_deno
# ------------------------------------------------------------------------------
run_deno() {
    local deno_install="$HOME/.deno"
    local bin_dir="$deno_install/bin"
    local exe="$bin_dir/deno"

    # -- Idempotency -----------------------------------------------------------
    if [[ -f "$exe" && -x "$exe" ]]; then
        success_message "Deno already installed, skipping."
        return 0
    fi

    # -- Architecture detection ------------------------------------------------
    local machine target
    machine=$(uname -m)
    case "$machine" in
        x86_64)  target="x86_64-unknown-linux-gnu"  ;;
        aarch64) target="aarch64-unknown-linux-gnu" ;;
        *)
            log_error "Unsupported architecture: $machine"
            return 1
            ;;
    esac

    # -- Fetch latest version --------------------------------------------------
    local version
    version=$(curl -fsSL https://dl.deno.land/release-latest.txt) || {
        log_error "Failed to fetch latest Deno version."
        return 1
    }

    local url="https://dl.deno.land/release/${version}/deno-${target}.zip"

    # -- Temp dir --------------------------------------------------------------
    local tmp_dir
    tmp_dir=$(mktemp -d) || { log_error "Failed to create temp directory."; return 1; }
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN

    local zip_path="$tmp_dir/deno.zip"

    # -- Download --------------------------------------------------------------
    run_with_spinner "Downloading Deno ${version}..." \
        curl -fsSL "$url" -o "$zip_path"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to download Deno."
        return 1
    fi

    # -- Extract ---------------------------------------------------------------
    mkdir -p "$bin_dir" || { log_error "Failed to create $bin_dir"; return 1; }

    if ! unzip -q -o "$zip_path" -d "$bin_dir"; then
        log_error "Failed to extract Deno."
        return 1
    fi

    chmod +x "$exe"

    # -- Shell setup -----------------------------------------------------------
    # Runs the official shell setup non-interactively (-y).
    run_with_spinner "Configuring Deno shell environment..." \
        "$exe" run -A --reload jsr:@deno/installer-shell-setup/bundled "$deno_install" -y

    if [[ $? -ne 0 ]]; then
        log_error "Deno shell setup failed."
        return 1
    fi

    success_message "Deno ${version} installed."
    return 0
}
