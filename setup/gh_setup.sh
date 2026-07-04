#!/bin/bash

# ─────────────────────────────────────────
# CONFIGURE THESE VARIABLES BEFORE RUNNING
# ─────────────────────────────────────────

GIT_NAME="Your Name"
GIT_EMAIL="12345678+username@users.noreply.github.com"  # from GitHub Settings → Emails
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"                    # path to your private key (without .pub)
ALLOWED_SIGNERS_FILE="$HOME/.ssh/allowed_signers"

# ─────────────────────────────────────────

set -e

PASS=true

# ── helpers ───────────────────────────────
ok()   { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; PASS=false; }
info() { echo "  → $1"; }
header() { echo ""; echo "[$1]"; }

# ── pre-flight checks ─────────────────────
header "Pre-flight checks"

# git installed?
if ! command -v git &>/dev/null; then
    fail "git is not installed. Install git and re-run."
    exit 1
fi
ok "git is installed ($(git --version))"

# placeholder values?
if [[ "$GIT_NAME" == "Your Name" ]]; then
    fail "GIT_NAME is still the placeholder. Edit the script before running."
    PASS=false
fi

if [[ "$GIT_EMAIL" == "12345678+username@users.noreply.github.com" ]]; then
    fail "GIT_EMAIL is still the placeholder. Edit the script before running."
    PASS=false
fi

# exit early if placeholders found
if [[ "$PASS" == false ]]; then
    echo ""
    echo "✗ Fix the errors above before running."
    exit 1
fi

ok "GIT_NAME is set: $GIT_NAME"
ok "GIT_EMAIL is set: $GIT_EMAIL"

# ~/.ssh directory permissions
SSH_DIR_PERMS=$(stat -c "%a" "$HOME/.ssh" 2>/dev/null || stat -f "%A" "$HOME/.ssh")
if [[ "$SSH_DIR_PERMS" != "700" ]]; then
    info "Fixing ~/.ssh directory permissions ($SSH_DIR_PERMS → 700)..."
    chmod 700 "$HOME/.ssh"
    ok "~/.ssh permissions fixed"
else
    ok "~/.ssh directory permissions are correct (700)"
fi

# private key exists?
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    fail "Private key not found at $SSH_KEY_PATH. Copy your keys to ~/.ssh/ and re-run."
    PASS=false
else
    ok "Private key found: $SSH_KEY_PATH"
fi

# public key exists?
if [[ ! -f "${SSH_KEY_PATH}.pub" ]]; then
    fail "Public key not found at ${SSH_KEY_PATH}.pub."
    PASS=false
else
    ok "Public key found: ${SSH_KEY_PATH}.pub"
fi

# private key permissions
KEY_PERMS=$(stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null || stat -f "%A" "$SSH_KEY_PATH")
if [[ "$KEY_PERMS" != "600" ]]; then
    info "Fixing private key permissions ($KEY_PERMS → 600)..."
    chmod 600 "$SSH_KEY_PATH"
    ok "Permissions fixed"
else
    ok "Private key permissions are correct (600)"
fi

if [[ "$PASS" == false ]]; then
    echo ""
    echo "✗ Fix the errors above before running."
    exit 1
fi

# ── git config ────────────────────────────
header "Configuring Git"

git config --global user.name "$GIT_NAME"
[[ "$(git config --global user.name)" == "$GIT_NAME" ]] \
    && ok "user.name = $GIT_NAME" \
    || { fail "user.name did not apply correctly"; PASS=false; }

git config --global user.email "$GIT_EMAIL"
[[ "$(git config --global user.email)" == "$GIT_EMAIL" ]] \
    && ok "user.email = $GIT_EMAIL" \
    || { fail "user.email did not apply correctly"; PASS=false; }

git config --global gpg.format ssh
[[ "$(git config --global gpg.format)" == "ssh" ]] \
    && ok "gpg.format = ssh" \
    || { fail "gpg.format did not apply correctly"; PASS=false; }

git config --global user.signingKey "${SSH_KEY_PATH}.pub"
[[ "$(git config --global user.signingKey)" == "${SSH_KEY_PATH}.pub" ]] \
    && ok "user.signingKey = ${SSH_KEY_PATH}.pub" \
    || { fail "user.signingKey did not apply correctly"; PASS=false; }

git config --global commit.gpgsign true
[[ "$(git config --global commit.gpgsign)" == "true" ]] \
    && ok "commit.gpgsign = true" \
    || { fail "commit.gpgsign did not apply correctly"; PASS=false; }

# ── allowed_signers ───────────────────────
header "Setting up allowed_signers"

mkdir -p "$(dirname "$ALLOWED_SIGNERS_FILE")"
PUBKEY=$(cat "${SSH_KEY_PATH}.pub")
SIGNERS_ENTRY="$GIT_EMAIL namespaces=\"git\" $PUBKEY"

if grep -qF "$PUBKEY" "$ALLOWED_SIGNERS_FILE" 2>/dev/null; then
    ok "Entry already exists in $ALLOWED_SIGNERS_FILE, skipping"
else
    echo "$SIGNERS_ENTRY" >> "$ALLOWED_SIGNERS_FILE"
    grep -qF "$PUBKEY" "$ALLOWED_SIGNERS_FILE" \
        && ok "Entry written to $ALLOWED_SIGNERS_FILE" \
        || { fail "Failed to write entry to $ALLOWED_SIGNERS_FILE"; PASS=false; }
fi

git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS_FILE"
[[ "$(git config --global gpg.ssh.allowedSignersFile)" == "$ALLOWED_SIGNERS_FILE" ]] \
    && ok "gpg.ssh.allowedSignersFile = $ALLOWED_SIGNERS_FILE" \
    || { fail "gpg.ssh.allowedSignersFile did not apply correctly"; PASS=false; }

# ── summary ───────────────────────────────
header "Summary"

echo ""
echo "  Git config:"
echo "    user.name              = $(git config --global user.name)"
echo "    user.email             = $(git config --global user.email)"
echo "    gpg.format             = $(git config --global gpg.format)"
echo "    user.signingKey        = $(git config --global user.signingKey)"
echo "    commit.gpgsign         = $(git config --global commit.gpgsign)"
echo "    allowed_signers file   = $(git config --global gpg.ssh.allowedSignersFile)"
echo ""
echo "  SSH key fingerprint:"
ssh-keygen -lf "${SSH_KEY_PATH}.pub"
echo ""
echo "  Public key to add on GitHub → Settings → SSH keys → New SSH key → Signing Key:"
echo ""
cat "${SSH_KEY_PATH}.pub"
echo ""
echo "  GitHub URL: https://github.com/settings/keys"
echo ""

if [[ "$PASS" == true ]]; then
    echo "✓ All checks passed."
else
    echo "✗ Some checks failed. Review the output above."
    exit 1
fi
