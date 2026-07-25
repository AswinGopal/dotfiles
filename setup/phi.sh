#!/bin/bash

# Tip: use Unsloth's bug-fixed quant (unsloth/Phi-4-mini-instruct-GGUF) if you
# can -- other conversions had EOS/pad-token mixups that could make generation
# run on past <|end|> or stop early. If output never stops cleanly, that's
# the likely cause.
DEFAULT_MODEL=$HOME/models/microsoft_Phi-4-mini-instruct-Q6_K_L.gguf
LLAMA_DIR=$HOME/models/llama-b10087/llama-cli
DEFAULT_CTX=8192
DEFAULT_DIFF_CHARS=20000

usage() {
    echo "Usage: $0 [-m <model_path>] [-c <context_size>] [-d <diff_chars>] [-f <diff_file>] [--debug] [--no-grammar]"
    echo "  -m            Path to the GGUF model (default: $DEFAULT_MODEL)"
    echo "  -c            Context window size    (default: $DEFAULT_CTX)"
    echo "  -d            Max diff chars         (default: $DEFAULT_DIFF_CHARS, 0 = unlimited)"
    echo "  -f            Path to a .txt file containing the git diff (overrides staged changes)"
    echo "  --debug       Print raw model output and suppress validation"
    echo "  --no-grammar  Disable the GBNF grammar that locks the first-line format"
    exit 1
}

MODEL=$DEFAULT_MODEL
CTX=$DEFAULT_CTX
DIFF_CHARS=$DEFAULT_DIFF_CHARS
DIFF_FILE=""
DEBUG=0
USE_GRAMMAR=1

# Pull out long flags before getopts (getopts doesn't handle long flags)
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --debug) DEBUG=1 ;;
        --no-grammar) USE_GRAMMAR=0 ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]}"

while getopts ":m:c:d:f:" opt; do
    case $opt in
        m) MODEL=$OPTARG ;;
        c) CTX=$OPTARG ;;
        d) DIFF_CHARS=$OPTARG ;;
        f) DIFF_FILE=$OPTARG ;;
        :) echo "Option -$OPTARG requires an argument."; usage ;;
        *) usage ;;
    esac
done

if [ ! -f "$MODEL" ]; then
    echo "Model not found: $MODEL"
    exit 1
fi

# Drops +/- diff lines that are PURELY a comment (single-line markers across
# common languages, plus /* */, """...""" and <!-- --> block comments tracked
# across multiple lines). Lines that mix real code with a trailing comment
# are left untouched -- this only removes comment-only lines/blocks.
strip_comments() {
    awk '
BEGIN { in_block = 0; block_end = "" }
in_block {
    if ($0 ~ block_end) { in_block = 0 }
    next
}
!/^[+-]/ { print; next }
/^--- / || /^\+\+\+ / { print; next }
{
    line = $0
    sub(/^[+-][[:space:]]*/, "", line)
    if (line ~ /^\/\*/ && line !~ /\*\//) { in_block = 1; block_end = "\\*/"; next }
    if (line ~ /^"""$/)                  { in_block = 1; block_end = "\"\"\""; next }
    if (line ~ /^<!--/ && line ~ /-->/)   { next }
    if (line ~ /^<!--/ && line !~ /-->/)  { in_block = 1; block_end = "-->"; next }
    if (line ~ /^(\/\/\/?|#|--|;|%)/)     { next }
    if (line ~ /^\/\*.*\*\/$/)            { next }
    print
}
'
}

# Builds the diff fed to the model out of three parts:
#   - the overall `git diff --cached --stat` summary (loose context only)
#   - FULL diffs (comment-stripped) for modified files ONLY
#   - just the filename/status for added/deleted/renamed/copied files
build_diff() {
    local status rest file

    git diff --cached --stat
    echo

    while IFS=$'\t' read -r status rest; do
        [ -z "$status" ] && continue
        case "$status" in
            M*)
                file="$rest"
                echo "--- $file (modified) ---"
                git diff --cached -- "$file" | strip_comments
                echo
                ;;
            A*) echo "--- $rest (added) ---" ;;
            D*) echo "--- $rest (deleted) ---" ;;
            R*) echo "--- ${rest/$'\t'/ -> } (renamed) ---" ;;
            C*) echo "--- ${rest/$'\t'/ -> } (copied) ---" ;;
            *)  echo "--- $rest (status $status) ---" ;;
        esac
    done < <(git diff --cached --name-status)
}

# Fetch the diff either from the provided file or from git staging
if [ -n "$DIFF_FILE" ]; then
    if [ ! -f "$DIFF_FILE" ]; then
        echo "Diff file not found: $DIFF_FILE"
        exit 1
    fi
    RAW_DIFF=$(cat "$DIFF_FILE")
else
    RAW_DIFF="$(build_diff)"
fi

if [ -z "$RAW_DIFF" ]; then
    if [ -n "$DIFF_FILE" ]; then
        echo "The provided diff file is empty."
    else
        echo "No staged changes. Run 'git add' first."
    fi
    exit 1
fi

if [ "$DIFF_CHARS" -eq 0 ]; then
    DIFF="$RAW_DIFF"
else
    DIFF=$(echo "$RAW_DIFF" | head -c "$DIFF_CHARS")
    if [ ${#RAW_DIFF} -gt "$DIFF_CHARS" ]; then
        echo "Warning: diff truncated to $DIFF_CHARS chars (full diff is ${#RAW_DIFF} chars). Use -d 0 to disable." >&2
    fi
fi

# Phi-4-mini-instruct is trained with a real system role, so rules live in
# -sys and only the diff goes in -p. --single-turn applies the model's own
# chat template automatically (<|system|>...<|end|><|user|>...<|end|><|assistant|>)
# -- no need to hand-write those tokens ourselves.
#
# P4-style prompt (from Wu et al. 2025, arXiv:2502.18904):
#   - System: role description + output constraints
#   - User:   few-shot demonstrations (CD) followed by the query diff (x_q)
SYSTEM_PROMPT=$(cat <<'EOF'
You are an expert software engineer specialising in code review and version control. Your task is to write a concise, accurate commit message for a given git diff.
EOF
)

USER_PROMPT="Code change:
${DIFF}
Commit message:"

# Grammar-constrained decoding: since this model isn't a reasoning model and
# tolerates low temperature well, we can make "type(scope): subject" the only
# thing the header is *able* to be -- the bracket-mimicry failure mode that
# shows up on weaker/reasoning models can't occur here. The body stays free.
GRAMMAR=$(cat <<'EOF'
root        ::= header "\n\n" body
header      ::= type scope? bang? ":" " " subject
type        ::= "feat" | "fix" | "docs" | "style" | "refactor" | "perf" | "test" | "chore" | "ci" | "build"
scope       ::= "(" scopechar+ ")"
scopechar   ::= [a-z0-9._/-]
bang        ::= "!"
subject     ::= subjectchar+
subjectchar ::= [^\n]
body        ::= bodychar*
bodychar    ::= [^\x00]
EOF
)

STDERR_DEST=/dev/null
[ "$DEBUG" -eq 1 ] && STDERR_DEST=/dev/stderr

GRAMMAR_ARGS=()
[ "$USE_GRAMMAR" -eq 1 ] && GRAMMAR_ARGS=(--grammar "$GRAMMAR")

raw=$($LLAMA_DIR \
    -m "$MODEL" \
    -c "$CTX" -fa on --no-warmup --log-disable \
    --no-display-prompt --simple-io --single-turn \
    --temp 0.6 -n 2048 \
    "${GRAMMAR_ARGS[@]}" \
    -sys "$SYSTEM_PROMPT" \
    -p "$USER_PROMPT" \
    2>"$STDERR_DEST")

if [ "$DEBUG" -eq 1 ]; then
    echo "=== RAW MODEL OUTPUT ===" >&2
    echo "$raw" >&2
    echo "========================" >&2
fi

output=$(echo "$raw" | awk '
    /^\[ Prompt:/ { exit }
    /^```/ { next }
    found { print }
    /^[a-z]+(\([^)]+\))?!?: .{4}/ { found=1; print }
')

# Validate the first line looks like a conventional commit
first_line=$(echo "$output" | head -1)
if ! echo "$first_line" | grep -qE '^[a-z]+(\([^)]+\))?!?: .{5,}'; then
    if [ "$DEBUG" -eq 0 ]; then
        echo "Failed to generate a valid commit message. Re-run with --debug to see raw output." >&2
    else
        echo "Validation failed — first line was: $(echo "$raw" | head -1)" >&2
    fi
    exit 1
fi

echo "$output"
