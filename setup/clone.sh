#!/bin/bash
#
# clone.sh — Robust GitHub repo cloner
#
# Verification: first checks the public GitHub API (no auth, no token) to
# see if the repo is public. If that can't confirm it (private repo, rate
# limit, network issue), falls back to `git ls-remote` over SSH, which uses
# your existing SSH key/agent to check real access — no token ever touches
# this script.
#
# By default, cloning always uses SSH, regardless of visibility (requires
# a working SSH key already added to your GitHub account).
#
# With -s / --setup, cloning uses HTTPS instead — but HTTPS mode only
# supports PUBLIC repos (no SSH fallback is attempted, and a private repo
# will cause an error, since HTTPS cloning of private repos needs a token
# this script does not use).
#
# Always clones into the current directory and confirms with you before
# doing anything.
#
# Usage:
#   ./clone.sh [username] [repo-name] [-s|--setup]
#
# If username/repo are omitted, you'll be prompted for them.

set -u

# === Colors ===
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
WHITE="\033[1;37m"
CYAN="\033[1;36m"
RC="\033[0m"

# === Helpers ===

err()  { echo -e "${RED}[X] $*${RC}"; }
ok()   { echo -e "${GREEN}[✔] $*${RC}"; }
warn() { echo -e "${YELLOW}[!] $*${RC}"; }
info() { echo -e "${WHITE}[*] $*${RC}"; }

command_exists() {
    command -v "$1" &> /dev/null
}

# === OS detection ===
# Sets global OS_ID to one of: ubuntu, arch, fedora
# Exits with an error for anything else (per user's request).
detect_os() {
    if [ ! -f /etc/os-release ]; then
        err "Cannot detect OS: /etc/os-release not found."
        exit 1
    fi

    local id
    id=$(. /etc/os-release && echo "$ID")

    case "$id" in
        ubuntu)
            OS_ID="ubuntu"
            ;;
        arch)
            OS_ID="arch"
            ;;
        fedora)
            OS_ID="fedora"
            ;;
        *)
            err "Unsupported OS: '$id'"
            echo -e "${WHITE}This script only supports Ubuntu, Arch Linux, and Fedora.${RC}"
            exit 1
            ;;
    esac
}

# === Detect if running in a live environment (e.g. Ubuntu live USB) ===
is_live_environment() {
    if grep -q "boot=casper" /proc/cmdline 2>/dev/null || [[ "$(findmnt -n -o FSTYPE / 2>/dev/null)" == "overlay" ]]; then
        return 0  # Live session
    else
        return 1  # Installed system
    fi
}

# === Enable Universe repository (Ubuntu only, only needed on live sessions) ===
# Note: does not run `apt-get update` itself — the caller runs it once,
# right before installing, regardless of whether this function did anything.
enable_universe_repo() {
    if ! grep -Rq "^deb .*universe" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        info "Enabling Universe repository..."
        if sudo add-apt-repository universe -y > /dev/null 2>&1; then
            ok "Universe repository enabled."
            return 0
        else
            err "Failed to enable Universe repository."
            return 1
        fi
    else
        ok "Universe repository already enabled."
        return 0
    fi
}

show_usage() {
    echo -e "Usage: $0 [github-username] [repo-name] [-s|--setup]"
    echo -e "  If username/repo are omitted, you will be prompted for them."
    echo -e "  Default: clones via SSH (works for public and private repos)."
    echo -e "  -s / --setup: clones via HTTPS instead (public repos only)."
    exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_usage
fi

# === Dependency check + install ===
install_dependencies() {
    local missing=()
    for cmd in curl jq git; do
        command_exists "$cmd" || missing+=("$cmd")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    warn "Missing required tools: ${missing[*]}"
    info "Installing missing dependencies for ${OS_ID}..."

    case "$OS_ID" in
        ubuntu)
            if is_live_environment; then
                if ! enable_universe_repo; then
                    err "Could not proceed without Universe repository."
                    exit 1
                fi
            fi

            sudo apt-get update > /dev/null 2>&1

            if sudo apt-get install -y "${missing[@]}" > /dev/null; then
                ok "All packages installed successfully."
            else
                err "Failed to install: ${missing[*]}"
                exit 1
            fi
            ;;
        fedora)
            if sudo dnf install -y "${missing[@]}" > /dev/null; then
                ok "All packages installed successfully."
            else
                err "Failed to install: ${missing[*]}"
                exit 1
            fi
            ;;
        arch)
            if sudo pacman -S --noconfirm --needed "${missing[@]}" > /dev/null; then
                ok "All packages installed successfully."
            else
                err "Failed to install: ${missing[*]}"
                exit 1
            fi
            ;;
    esac

    # Re-check: fail loudly if something still isn't on PATH after install
    local still_missing=()
    for cmd in "${missing[@]}"; do
        command_exists "$cmd" || still_missing+=("$cmd")
    done
    if [ ${#still_missing[@]} -gt 0 ]; then
        err "Still missing after install attempt: ${still_missing[*]}"
        exit 1
    fi
}

# === Query public GitHub API for repo info (unauthenticated, no token) ===
# Sets globals: API_STATUS (found|notfound|error), REPO_PRIVATE (true|false)
query_repo_info() {
    local user="$1"
    local repo="$2"
    local response http_code body

    response=$(curl -s -w "\n%{http_code}" "https://api.github.com/repos/${user}/${repo}")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    case "$http_code" in
        200)
            API_STATUS="found"
            REPO_PRIVATE=$(echo "$body" | jq -r '.private')
            ;;
        404)
            API_STATUS="notfound"
            ;;
        403)
            API_STATUS="error"
            ;;
        *)
            API_STATUS="error"
            ;;
    esac
}

# === Check repo access via SSH (works for private repos you own/collaborate on) ===
# Uses your existing SSH key/agent — no token, no password, no API auth involved.
# Returns 0 if the repo is reachable over SSH with your current credentials.
check_repo_via_ssh() {
    local user="$1"
    local repo="$2"
    git ls-remote "git@github.com:${user}/${repo}.git" &> /dev/null
    return $?
}

# === Prompt for yes/no ===
# Usage: confirm "Question?" [default]
#   default: "y" or "n" (optional). If set, pressing Enter with no input
#   accepts that default. If omitted, an empty answer re-prompts.
confirm() {
    local prompt="$1"
    local default="${2:-}"
    local suffix reply

    case "$default" in
        y) suffix="[Y/n]" ;;
        n) suffix="[y/N]" ;;
        *) suffix="[y/n]" ;;
    esac

    while true; do
        read -r -p "$(echo -e "${CYAN}${prompt} ${suffix}: ${RC}")" reply
        if [ -z "$reply" ] && [ -n "$default" ]; then
            reply="$default"
        fi
        case "$reply" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

# === Main ===

detect_os
install_dependencies

USERNAME="${1:-}"
REPO_NAME="${2:-}"
SETUP_MODE=false

case "${3:-}" in
    -s|--setup)
        SETUP_MODE=true
        ;;
esac

while true; do
    # Prompt for anything missing
    if [ -z "$USERNAME" ]; then
        read -r -p "$(echo -e "${CYAN}GitHub username: ${RC}")" USERNAME
    fi
    if [ -z "$REPO_NAME" ]; then
        read -r -p "$(echo -e "${CYAN}Repo name: ${RC}")" REPO_NAME
    fi

    if [ -z "$USERNAME" ] || [ -z "$REPO_NAME" ]; then
        err "Username and repo name cannot be empty."
        USERNAME=""
        REPO_NAME=""
        continue
    fi

    info "Looking up ${USERNAME}/${REPO_NAME} on GitHub..."
    query_repo_info "$USERNAME" "$REPO_NAME"

    if [ "$API_STATUS" == "found" ]; then
        if [ "$REPO_PRIVATE" == "true" ]; then
            ok "Repo found (private): ${USERNAME}/${REPO_NAME}"
        else
            ok "Repo found (public): ${USERNAME}/${REPO_NAME}"
        fi
        break
    fi

    if [ "$SETUP_MODE" = true ]; then
        # Setup mode is HTTPS-only, public repos only — no SSH fallback.
        if [ "$API_STATUS" == "notfound" ]; then
            err "Repo not found (public API): ${USERNAME}/${REPO_NAME}"
            echo -e "${WHITE}(-s/--setup only clones public repos over HTTPS.)${RC}"
        else
            err "Could not verify repo via GitHub API (rate limit or network issue)."
        fi
        if confirm "Re-enter username/repo?" y; then
            USERNAME=""
            REPO_NAME=""
            continue
        else
            info "Aborted by user."
            exit 1
        fi
    fi

    # Public API couldn't confirm it — could be a typo, someone else's private
    # repo, or a private repo YOU have SSH access to. Check via SSH directly;
    # this uses your existing key/agent and never touches a token or the API.
    if [ "$API_STATUS" == "notfound" ]; then
        warn "Not visible via public API — checking SSH access (may be private)..."
    else
        warn "GitHub API unavailable (rate limit or network) — checking SSH access instead..."
    fi

    if check_repo_via_ssh "$USERNAME" "$REPO_NAME"; then
        ok "Repo found via SSH: ${USERNAME}/${REPO_NAME} (private, you have access)"
        API_STATUS="found_ssh"
        REPO_PRIVATE="true"
        break
    fi

    err "Repo not accessible: ${USERNAME}/${REPO_NAME}"
    echo -e "${WHITE}(Checked both the public API and SSH — not found, or you don't have access.)${RC}"
    if confirm "Re-enter username/repo?" y; then
        USERNAME=""
        REPO_NAME=""
        continue
    else
        info "Aborted by user."
        exit 1
    fi
done

# === Determine visibility & protocol ===
if [ "$REPO_PRIVATE" == "true" ]; then
    VISIBILITY="private"
else
    VISIBILITY="public"
fi

if [ "$SETUP_MODE" = true ]; then
    if [ "$VISIBILITY" == "private" ]; then
        err "-s/--setup only supports public repos. This repo is private."
        echo -e "${WHITE}Re-run without -s/--setup to clone it via SSH instead.${RC}"
        exit 1
    fi
    PROTOCOL="https"
else
    PROTOCOL="ssh"
fi

# === Build URL & destination ===
if [ "$PROTOCOL" == "https" ]; then
    REPO_URL="https://github.com/${USERNAME}/${REPO_NAME}.git"
else
    REPO_URL="git@github.com:${USERNAME}/${REPO_NAME}.git"
fi

DEST_DIR="$(pwd)"
CLONE_DIR="${DEST_DIR}/${REPO_NAME}"

if [ -e "$CLONE_DIR" ]; then
    err "Target already exists: $CLONE_DIR"
    echo -e "${WHITE}Remove it or run this script from a different directory.${RC}"
    exit 1
fi

# === Final confirmation summary ===
echo ""
echo -e "${WHITE}=== Clone Summary ===${RC}"
echo -e "  Username     : ${USERNAME}"
echo -e "  Repo         : ${REPO_NAME}"
echo -e "  Visibility   : ${VISIBILITY:-unknown}"
echo -e "  Protocol     : ${PROTOCOL^^}"
echo -e "  Clone URL    : ${REPO_URL}"
echo -e "  Destination  : ${CLONE_DIR}"
echo ""

if ! confirm "Proceed with clone?" y; then
    info "Aborted by user."
    exit 1
fi

# === Clone ===
info "Cloning ${REPO_NAME}..."
if git clone -q "$REPO_URL" "$CLONE_DIR"; then
    ok "Repo cloned successfully to: $CLONE_DIR"
else
    err "Clone failed. Check your access/auth and try again."
    exit 1
fi
