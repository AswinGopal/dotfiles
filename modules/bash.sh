#!/bin/bash

# modules/bash.sh
#
# Deploy bash dotfiles from bashfiles/$OS_ID/ to $HOME/ as hidden files.
# Files named e.g. "bashrc" and "bash_aliases" are installed as "~/.bashrc"
# and "~/.bash_aliases".
#
# Backs up $HOME/.bashrc before deploying. Backup failure is a hard stop —
# we never overwrite without a backup in place.
#
# Scope: file deployment only. git_info download belongs to binaries.sh.
# Shell tool init (zoxide/fzf/uv) belongs to shell_tools.sh.
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
    local src_dir="$REPO_ROOT/bashfiles/$OS_ID"
    local bashrc="$HOME/.bashrc"

    if [[ ! -d "$src_dir" ]]; then
        log_error "Bash config source not found: $src_dir"
        return 1
    fi

    # Back up .bashrc before overwriting. Skip if it does not yet exist
    # (e.g. a minimal live environment).
    if [[ -f "$bashrc" ]]; then
        if ! cp "$bashrc" "${bashrc}.backup"; then
            log_error "Failed to back up $bashrc — aborting to avoid data loss."
            return 1
        fi
    fi

    # Deploy all files from bashfiles/$OS_ID/ as hidden files in $HOME.
    # Continue on per-file failure but record it — all files are attempted.
    local failed=0
    local file filename
    for file in "$src_dir/"*; do
        filename=$(basename "$file")
        if ! cp "$file" "$HOME/.$filename"; then
            log_error "Failed to copy $filename to ~/.$filename"
            failed=1
        fi
    done

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "Bash dotfiles deployed."
    return 0
}
