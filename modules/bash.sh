#!/bin/bash

# modules/bash.sh
#
# Downloads starshell, deploys bash_aliases (per-OS), copies starship.toml,
# and appends the starshell init hook + ~/.local/bin PATH setup to the
# existing ~/.bashrc.
#
# bashrc is appended to, never overwritten — each distro ships its own.
# append_if_missing (lib/utils.sh) requires the target file to exist;
# a missing ~/.bashrc is treated as a failure.
#
# Reads:
#   REPO_ROOT — set by install.sh
#   OS_ID     — set by install.sh (arch | fedora | ubuntu)
#
# Public interface: run_bash()

# ------------------------------------------------------------------------------
# run_bash
# ------------------------------------------------------------------------------
run_bash() {
    local aliases_src="$REPO_ROOT/bashfiles/$OS_ID/bash_aliases"
    local aliases_dest="$HOME/.bash_aliases"
    local starship_src="$REPO_ROOT/bashfiles/starship.toml"
    local starship_dest="$HOME/.config"
    local starshell_url="https://github.com/AswinGopal/starshell/releases/latest/download/starshell"
    local starshell_dest="$HOME/.local/bin"
    local bashrc="$HOME/.bashrc"
    local failed=0

    # -- starshell: prompt-rendering binary --------------------------------------
    mkdir -p "$starshell_dest" || { log_error "Failed to create $starshell_dest"; failed=1; }

    if ! download_binary "starshell" "$starshell_url" "$starshell_dest/starshell"; then
        log_error "Failed to download starshell"
        failed=1
    fi

    # -- bash_aliases: per-OS content, still a full deploy ----------------------
    if [[ ! -f "$aliases_src" ]]; then
        log_error "bash_aliases source not found: $aliases_src"
        failed=1
    else
        if [[ -f "$aliases_dest" ]]; then
            if ! cp "$aliases_dest" "${aliases_dest}.backup"; then
                log_error "Failed to back up $aliases_dest"
                failed=1
            fi
        fi

        if ! cp "$aliases_src" "$aliases_dest"; then
            log_error "Failed to deploy bash_aliases to $aliases_dest"
            failed=1
        fi
    fi

    # -- starship.toml: config for starshell -------------------------------------
    if [[ ! -f "$starship_src" ]]; then
        log_error "starship.toml not found: $starship_src"
        failed=1
    else
        mkdir -p "$starship_dest" || { log_error "Failed to create $starship_dest"; failed=1; }

        if [[ -f "$starship_dest/starship.toml" ]]; then
            if ! cp "$starship_dest/starship.toml" "$starship_dest/starship.toml.backup"; then
                log_error "Failed to back up $starship_dest/starship.toml"
                failed=1
            fi
        fi

        if ! cp "$starship_src" "$starship_dest/starship.toml"; then
            log_error "Failed to deploy starship.toml to $starship_dest"
            failed=1
        fi
    fi

    # -- bashrc: append-only, never overwritten ----------------------------------
    if [[ ! -f "$bashrc" ]]; then
        log_error "$bashrc not found — cannot append starshell/PATH setup."
        failed=1
    elif ! cp "$bashrc" "${bashrc}.backup"; then
        log_error "Failed to back up $bashrc — skipping starshell/PATH setup."
        failed=1
    else
        if ! append_if_missing "$bashrc" 'starshell init bash' \
            'eval "$(starshell init bash)"'; then
            log_error "Failed to append starshell init to $bashrc"
            failed=1
        fi

        if ! append_if_missing "$bashrc" '$HOME/.local/bin' \
            'export PATH="$HOME/.local/bin:$PATH"'; then
            log_error "Failed to append .local/bin PATH export to $bashrc"
            failed=1
        fi
    fi

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "Bash dotfiles deployed."
    return 0
}