#!/usr/bin/env bash

# install.sh
#
# Entry point for the dotfiles unified setup.
#
# Flow:
#   1.  Set REPO_ROOT, LOG_FILE, PATH
#   2.  Detect OS from /etc/os-release
#   3.  Source lib/utils.sh → lib/pkg.sh → os/$OS_ID.sh
#   4.  bootstrap_deps()  — install curl jq tar wget unzip sed git
#   5.  bootstrap_gum()   — download gum binary to ~/.local/bin/gum
#   --- gum available from here ---
#   6.  Source lib/ui.sh → all modules/*.sh
#   7.  show_checklist()  — user selects modules → SELECTED_MODULES
#   8.  Run loop          — run_<module>(); RESULTS[key]=$? for each selection
#   9.  show_summary()

# ==============================================================================
# GLOBALS
# ==============================================================================

# Try git first (normal clone); fall back to script location (tarball download).
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
    || REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# LOG_FILE must be exported — log_write() uses it inside gum spin subprocesses.
export LOG_FILE="$REPO_ROOT/install.log"

# Prepend ~/.local/bin so gum is reachable after bootstrap_gum, and binaries
# installed by the binaries module are immediately available.
export PATH="$HOME/.local/bin:$PATH"

# ==============================================================================
# OS DETECTION  (plain echo — gum not yet available)
# ==============================================================================

OS_ID=$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')

case "$OS_ID" in
    arch|fedora|ubuntu) ;;
    *)
        echo "Error: Unsupported or undetected OS '${OS_ID:-unknown}'." >&2
        echo "Supported: arch, fedora, ubuntu." >&2
        exit 1
        ;;
esac

echo "Detected OS: $OS_ID"

# ==============================================================================
# PRE-GUM SOURCING
#
# Order is load-order-dependent — do not reorder.
#   utils.sh  → log_write available (used by pkg_install in os/*.sh)
#   pkg.sh    → guard pkg_install() installed
#   os/*.sh   → real pkg_install() overwrites guard; MODULES array declared
# ==============================================================================

source "$REPO_ROOT/lib/utils.sh"
source "$REPO_ROOT/lib/pkg.sh"
source "$REPO_ROOT/os/$OS_ID.sh"

# ==============================================================================
# BOOTSTRAP  (plain echo — gum not yet available)
# ==============================================================================

# ------------------------------------------------------------------------------
# bootstrap_deps
#
# Install hard dependencies required by install.sh and bootstrap_gum.
# pkg_install() is now available from os/$OS_ID.sh. All three package managers
# handle already-installed packages natively — one call, no filtering needed.
# ------------------------------------------------------------------------------
bootstrap_deps() {
    echo "Installing dependencies..."
    if ! pkg_install curl jq tar wget unzip sed git; then
        echo "Error: Failed to install required dependencies." >&2
        exit 1
    fi
    echo "Dependencies ready."
}

# ------------------------------------------------------------------------------
# bootstrap_gum
#
# Download the gum binary from the latest charmbracelet/gum GitHub release
# to ~/.local/bin/gum and make it executable.
#
# Idempotent: skips silently if the binary already exists and is executable.
#
# Architecture mapping:
#   uname -m returns aarch64 on ARM hardware; gum release assets use arm64.
#   x86_64 passes through unchanged.
#
# Extraction: tar --wildcards '*/gum' --strip-components=1 strips the versioned
# directory prefix (e.g. gum_0.17.0_Linux_x86_64/) regardless of version number,
# landing the binary directly at ~/.local/bin/gum.
# ------------------------------------------------------------------------------
bootstrap_gum() {
    local gum_dest="$HOME/.local/bin/gum"

    if [[ -f "$gum_dest" && -x "$gum_dest" ]]; then
        return 0
    fi

    echo "Preparing setup..."

    # Arch detection
    local machine arch
    machine=$(uname -m)
    case "$machine" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="arm64"  ;;
        *)
            echo "Error: Unsupported architecture '$machine'." >&2
            exit 1
            ;;
    esac

    # Fetch latest release metadata
    local release_json
    release_json=$(curl -fsSL "https://api.github.com/repos/charmbracelet/gum/releases/latest") || {
        echo "Error: Failed to fetch gum release info from GitHub API." >&2
        exit 1
    }

    # Resolve tarball URL for this arch
    local url
    url=$(printf '%s' "$release_json" \
        | jq -r ".assets[] | select(.name | test(\"gum_.*_Linux_${arch}\\\\.tar\\\\.gz$\")) | .browser_download_url")

    if [[ -z "$url" ]]; then
        echo "Error: Could not resolve gum download URL for arch '$arch'." >&2
        exit 1
    fi

    # Download tarball to a temp file; clean up on both success and failure.
    local tmp_tarball
    tmp_tarball=$(mktemp --suffix=.tar.gz) || {
        echo "Error: Failed to create temp file for gum tarball." >&2
        exit 1
    }

    if ! curl -fsSL "$url" -o "$tmp_tarball"; then
        rm -f "$tmp_tarball"
        echo "Error: Failed to download gum." >&2
        exit 1
    fi

    mkdir -p "$HOME/.local/bin"

    local tmp_extract
    tmp_extract=$(mktemp -d) || {
        rm -f "$tmp_tarball"
        echo "Error: Failed to create temp directory for gum extraction." >&2
        exit 1
    }

    if ! tar -xzf "$tmp_tarball" -C "$tmp_extract"; then
        rm -f "$tmp_tarball"
        rm -rf "$tmp_extract"
        echo "Error: Failed to extract gum tarball." >&2
        exit 1
    fi

    rm -f "$tmp_tarball"

    local gum_bin
    gum_bin=$(find "$tmp_extract" -type f -name "gum" | head -1)

    if [[ -z "$gum_bin" ]]; then
        rm -rf "$tmp_extract"
        echo "Error: gum binary not found in tarball." >&2
        exit 1
    fi

    if ! mv "$gum_bin" "$gum_dest"; then
        rm -rf "$tmp_extract"
        echo "Error: Failed to move gum binary to $gum_dest." >&2
        exit 1
    fi

    rm -rf "$tmp_extract"
    chmod +x "$gum_dest"
}

bootstrap_deps
bootstrap_gum

# ==============================================================================
# POST-GUM SOURCING
#
# All modules are sourced regardless of OS — the MODULES array (declared by
# os/$OS_ID.sh) controls which run_<module>() functions are actually called.
# Sourcing a module for another distro is harmless; it just loads unused functions.
# ==============================================================================

source "$REPO_ROOT/lib/ui.sh"

for _module in "$REPO_ROOT/modules/"*.sh; do
    source "$_module"
done

# ==============================================================================
# ORCHESTRATION
# ==============================================================================

# Present the module checklist. Populates the global SELECTED_MODULES array.
show_checklist

# Build a key → label lookup from MODULES for run-loop announcements.
# MODULES is declared by os/$OS_ID.sh; format: "key|Display Label|default".
declare -A _label_map
for _entry in "${MODULES[@]}"; do
    IFS='|' read -r _k _l _d <<< "$_entry"
    _label_map["$_k"]="$_l"
done

# Run each selected module in SELECTED_MODULES order.
# Failures are recorded in RESULTS and execution always continues —
# a failing module must never prevent subsequent modules from running.
declare -A RESULTS

for key in "${SELECTED_MODULES[@]}"; do
    show_info "Running: ${_label_map[$key]:-$key}..."
    "run_${key}"
    RESULTS["$key"]=$?
done

show_summary
