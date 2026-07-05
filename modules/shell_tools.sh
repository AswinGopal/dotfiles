#!/bin/bash

# modules/shell_tools.sh
#
# Generate init/completion files and append source lines to $HOME/.bashrc for:
#   zoxide — init script written to ~/.zoxide_init.bash
#   fzf    — no file; eval line appended directly to .bashrc
#   uv     — completion script written to ~/.uv-completion.bash
#
# All three tools are treated as best-effort: if a tool is absent or its init
# command fails, log_error is called and the module moves on. The module only
# returns 1 if $HOME/.bashrc does not exist — append_if_missing requires the
# file to exist, and without it none of the three steps can succeed.
#
# Idempotency: append_if_missing is idempotent. Generation commands overwrite
# their output files on each run, which is harmless.
#
# No spinner: all operations are sub-second CLI invocations and file writes.
#
# Public interface: run_shell_tools()

# ------------------------------------------------------------------------------
# run_shell_tools
# ------------------------------------------------------------------------------
run_shell_tools() {
    local bashrc="$HOME/.bashrc"

    if [[ ! -f "$bashrc" ]]; then
        log_error "$bashrc not found — run the bash module first."
        return 1
    fi

    # -- zoxide ----------------------------------------------------------------
    if command -v zoxide &>/dev/null; then
        if ! zoxide init bash > "$HOME/.zoxide_init.bash"; then
            log_error "zoxide init failed."
        else
            append_if_missing "$bashrc" "zoxide_init.bash" \
                $'# Initialize Zoxide\n[ -f "$HOME/.zoxide_init.bash" ] && source "$HOME/.zoxide_init.bash"' \
                || log_error "Failed to update .bashrc for zoxide."
            success_message "zoxide configured."
        fi
    else
        log_error "zoxide not found, skipping."
    fi

    # -- fzf -------------------------------------------------------------------
    if command -v fzf &>/dev/null; then
        append_if_missing "$bashrc" "fzf --bash" \
            $'# Set up fzf key bindings and fuzzy completion\neval "$(fzf --bash)"' \
            || log_error "Failed to update .bashrc for fzf."
        success_message "fzf configured."
    else
        log_error "fzf not found, skipping."
    fi

    # -- uv --------------------------------------------------------------------
    if command -v uv &>/dev/null; then
        if ! uv generate-shell-completion bash > "$HOME/.uv-completion.bash"; then
            log_error "uv shell completion generation failed."
        else
            append_if_missing "$bashrc" "uv-completion.bash" \
                $'# Initialize uv completion\n[ -f "$HOME/.uv-completion.bash" ] && source "$HOME/.uv-completion.bash"' \
                || log_error "Failed to update .bashrc for uv."
            success_message "uv configured."
        fi
    else
        log_error "uv not found, skipping."
    fi

    success_message "Shell tools configured."
    return 0
}
