#!/bin/bash

# modules/bash.sh
#
# Downloads git_info, deploys bash_aliases (per-OS), and appends PS1 +
# ~/.local/bin PATH setup to the existing ~/.bashrc.
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
    local ps1_src="$REPO_ROOT/bashfiles/ps1"
    local aliases_dest="$HOME/.bash_aliases"
    local bashrc="$HOME/.bashrc"
    local bin_dir="$HOME/.local/bin"
    local git_info_url="https://github.com/AswinGopal/git_info/releases/latest/download/git_info"
    local failed=0

    # -- git_info: sole dependency of the PS1 git segment ------------------------
    mkdir -p "$bin_dir" || { log_error "Failed to create $bin_dir"; failed=1; }

    if ! download_binary "git_info" "$git_info_url" "$bin_dir/git_info"; then
        log_error "Failed to download git_info — PS1 git segment will be unavailable."
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

    # -- bashrc: append-only, never overwritten ----------------------------------
    if [[ ! -f "$bashrc" ]]; then
        log_error "$bashrc not found — cannot append PS1/PATH setup."
        failed=1
    elif ! cp "$bashrc" "${bashrc}.backup"; then
        log_error "Failed to back up $bashrc — skipping PS1/PATH setup."
        failed=1
    else
        if [[ ! -f "$ps1_src" ]]; then
            log_error "PS1 source not found: $ps1_src"
            failed=1
        else
            local ps1_content
            ps1_content=$(<"$ps1_src")

            if ! append_if_missing "$bashrc" "# Powerline segment colors" "$ps1_content"; then
                log_error "Failed to append PS1 setup to $bashrc"
                failed=1
            fi
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
