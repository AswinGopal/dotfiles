#!/bin/bash

# lib/ui.sh
#
# All terminal output and interactive UI primitives.
#
# CONTRACT:
#   - Sourced only after gum bootstrap is complete (install.sh guarantees this).
#   - Every gum invocation uses $GUM — never bare 'gum' — to remain independent
#     of PATH state at source time.
#   - Log functions write to stderr and the log file. stdout is reserved for
#     data that callers may capture (e.g. show_checklist → SELECTED_MODULES).
#   - No function calls exit. Callers own control flow.
#
# Global state this file reads:
#   MODULES          — set by os/<distro>.sh. Format: "key|Label|on|off" per entry.
#   LOG_FILE         — set by install.sh before any sourcing.
#
# Global state this file writes:
#   SELECTED_MODULES — associative array populated by show_checklist.
#   RESULTS          — associative array read by show_summary.

GUM="$HOME/.local/bin/gum"

# ANSI color codes — used only in log functions, not in gum-rendered UI.
readonly _RC='\e[0m'
readonly _RED='\e[1;38;2;255;51;51m'
readonly _GREEN='\e[1;32m'
readonly _YELLOW='\e[1;33m'

# ------------------------------------------------------------------------------
# log_error "message"
#
# Report a non-fatal error. Writes to stderr (visible during spinner) and log.
# Modules call this before returning 1.
# ------------------------------------------------------------------------------
log_error() {
    local msg="$1"
    printf "${_RED}Error: %s${_RC}\n" "$msg" >&2
    log_write "ERROR" "$msg"
}

# ------------------------------------------------------------------------------
# show_info "message"
#
# Announce the start of a logical operation within a module.
# ------------------------------------------------------------------------------
show_info() {
    printf "\n${_YELLOW}INFO: %s${_RC}\n" "$1" >&2
}

# ------------------------------------------------------------------------------
# success_message "message"
#
# Confirm successful completion of an operation.
# ------------------------------------------------------------------------------
success_message() {
    printf "${_GREEN}%s ✓${_RC}\n" "$1" >&2
}

# ------------------------------------------------------------------------------
# run_with_spinner "label" cmd [args...]
#
# Wrap a slow operation in a gum spinner.
#
# gum spin by default suppresses the wrapped command's stdout. stderr passes
# through — meaning error output from the wrapped command surfaces immediately
# even while the spinner is active. This is intentional and correct: errors
# must never be swallowed by cosmetic UI.
#
# Returns the exit code of the wrapped command unchanged.
# ------------------------------------------------------------------------------
run_with_spinner() {
    local label="$1"
    shift
    "$GUM" spin --title "$label" -- "$@"
}

# ------------------------------------------------------------------------------
# gum_confirm "question"
#
# Prompt the user for a yes/no confirmation.
# Returns: 0 if confirmed, 1 if declined or Ctrl-C.
# ------------------------------------------------------------------------------
gum_confirm() {
    "$GUM" confirm "$1"
}

# ------------------------------------------------------------------------------
# gum_input "placeholder"
#
# Prompt the user for a single line of text input.
# Writes the entered value to stdout so callers can capture it:
#   value=$(gum_input "Enter profile name")
# ------------------------------------------------------------------------------
gum_input() {
    "$GUM" input --placeholder "$1"
}

# ------------------------------------------------------------------------------
# show_checklist
#
# Build an interactive checklist from the MODULES array declared by os/<distro>.sh.
# Populates the global SELECTED_MODULES array with the keys the user confirmed.
#
# MODULES format (each element):
#   "key|Display Label|default"
#   default is either "on" or "off"
#
# Implementation notes:
#   gum choose --no-limit accepts a list of items and returns the selected ones,
#   one per line. To map selected labels back to keys (gum works with display
#   strings, not opaque keys), we build two parallel arrays — _keys and _labels —
#   at parse time, then reverse-map after gum returns.
#
#   Pre-selected items are passed via --selected, which accepts a comma-separated
#   list of display labels to highlight by default.
# ------------------------------------------------------------------------------
show_checklist() {
    declare -g -a SELECTED_MODULES=()

    local -a _keys=()
    local -a _labels=()
    local -a _preselected_labels=()

    local entry key label default
    for entry in "${MODULES[@]}"; do
        IFS='|' read -r key label default <<< "$entry"
        _keys+=("$key")
        _labels+=("$label")
        [[ "$default" == "on" ]] && _preselected_labels+=("$label")
    done

    local preselected_str
    preselected_str=$(IFS=,; echo "${_preselected_labels[*]}")

    # gum choose writes selected labels to stdout, one per line.
    local chosen
    chosen=$(
        "$GUM" choose --no-limit \
            --selected="$preselected_str" \
            --header="Select modules to run (↑↓ navigate, x select, enter confirm)" \
            "${_labels[@]}"
    ) || {
        # User pressed Ctrl-C or Escape — treat as clean exit, not an error.
        printf "\nSetup cancelled.\n" >&2
        exit 0
    }

    # Reverse-map chosen labels → keys, preserving MODULES declaration order.
    local i label_i
    for (( i=0; i<${#_keys[@]}; i++ )); do
        label_i="${_labels[$i]}"
        if grep -qF "$label_i" <<< "$chosen"; then
            SELECTED_MODULES+=("${_keys[$i]}")
        fi
    done
}

# ------------------------------------------------------------------------------
# show_summary
#
# Render a per-module pass/fail table after the run completes.
# Reads MODULES (for display order and labels) and RESULTS (associative array
# of key → exit code set by install.sh after each module runs).
#
# MODULES order is authoritative — RESULTS is an associative array and has no
# guaranteed iteration order.
# ------------------------------------------------------------------------------
show_summary() {
    local -a lines=()
    local entry key label default status_str result_code

    for entry in "${MODULES[@]}"; do
        IFS='|' read -r key label default <<< "$entry"

        # Only show modules that were selected and run.
        [[ -v "RESULTS[$key]" ]] || continue

        result_code="${RESULTS[$key]}"

        if [[ "$result_code" -eq 0 ]]; then
            status_str="$("$GUM" style --foreground 2 "✓  $label")"
        else
            status_str="$("$GUM" style --foreground 1 "✗  $label")"
        fi

        lines+=("$status_str")
    done

    printf '\n'
    "$GUM" style \
        --border normal \
        --padding "1 2" \
        --border-foreground 240 \
        --bold \
        "Setup Summary"

    printf '%s\n' "${lines[@]}"
    printf '\n'
}