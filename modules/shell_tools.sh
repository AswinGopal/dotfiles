#!/bin/bash

# modules/shell_tools.sh
#
# Installs zoxide, fzf, uv and configures shell init for each in ~/.bashrc:
#   zoxide — init script written to ~/.zoxide_init.bash, sourced
#   fzf    — eval line appended directly
#   uv     — completion script written to ~/.uv-completion.bash, sourced
#
# Each tool is installed and configured independently — a failure in one
# does not block the others, but any failure causes the module to return 1.
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

    local failed=0

    if ! cp "$bashrc" "${bashrc}.backup"; then
        log_error "Failed to back up $bashrc — skipping shell tool setup."
        return 1
    fi

    # pkg_install and log_write are bash functions; export them so the bash
    # subprocess spawned by gum spin can resolve them.
    export -f pkg_install
    export -f log_write

    # -- zoxide ----------------------------------------------------------------
    if ! run_with_spinner "Installing zoxide..." bash -c 'pkg_install "$@"' _ zoxide; then
        log_error "Failed to install zoxide."
        failed=1
    elif ! zoxide init bash > "$HOME/.zoxide_init.bash"; then
        log_error "zoxide init failed."
        failed=1
    elif ! append_if_missing "$bashrc" "zoxide_init.bash" \
        $'# Initialize Zoxide\n[ -f "$HOME/.zoxide_init.bash" ] && source "$HOME/.zoxide_init.bash"'; then
        log_error "Failed to update .bashrc for zoxide."
        failed=1
    else
        success_message "zoxide configured."
    fi

    # -- fzf -------------------------------------------------------------------
    if ! run_with_spinner "Installing fzf..." bash -c 'pkg_install "$@"' _ fzf; then
        log_error "Failed to install fzf."
        failed=1
    elif ! append_if_missing "$bashrc" "fzf --bash" \
        $'# Set up fzf key bindings and fuzzy completion\neval "$(fzf --bash)"'; then
        log_error "Failed to update .bashrc for fzf."
        failed=1
    else
        success_message "fzf configured."
    fi

    # -- uv --------------------------------------------------------------------
    if ! run_with_spinner "Installing uv..." bash -c 'pkg_install "$@"' _ uv; then
        log_error "Failed to install uv."
        failed=1
    elif ! uv generate-shell-completion bash > "$HOME/.uv-completion.bash"; then
        log_error "uv shell completion generation failed."
        failed=1
    elif ! append_if_missing "$bashrc" "uv-completion.bash" \
        $'# Initialize uv completion\n[ -f "$HOME/.uv-completion.bash" ] && source "$HOME/.uv-completion.bash"'; then
        log_error "Failed to update .bashrc for uv."
        failed=1
    else
        success_message "uv configured."
    fi

    if [[ $failed -ne 0 ]]; then
        return 1
    fi

    success_message "Shell tools configured."
    return 0
}
