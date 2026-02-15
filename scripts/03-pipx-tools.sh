#!/usr/bin/env bash
# ===========================================================================
# 03-pipx-tools.sh -- Install public Python tools via pipx
# ===========================================================================
#
# This script reads lists/pipx-tools.txt and installs each tool using pipx.
#
# WHY pipx OVER pip?
# ------------------
# pip installs packages into a shared Python environment.  If two tools
# depend on different versions of the same library (e.g. requests==2.28 vs
# requests==2.31), they conflict and one breaks.
#
# pipx solves this by creating an isolated virtual environment (venv) for
# every tool.  Each tool gets its own copy of its dependencies, completely
# separate from every other tool.  The tool's CLI entry-point is then
# symlinked into ~/.local/bin so you can run it from anywhere.
#
# Think of it like: pip = shared apartment, pipx = everyone gets their own
# flat but the hallway (PATH) connects them all.
#
# INSTALL METHODS
# ---------------
# pipx supports two main install methods:
#
#   pipx install TOOL          Install a package by name from PyPI (the
#                              Python Package Index at pypi.org).  This is
#                              what we use for public, published tools.
#
#   pipx install git+URL      Install directly from a git repository.  Use
#                              this when a tool is not on PyPI, or when you
#                              need a fork/branch.  Example:
#                                pipx install git+https://github.com/user/repo.git
#                              Our BLS forks use this method in a separate
#                              script (bls-tools.txt).
#
# USAGE
# -----
#   sudo ./scripts/03-pipx-tools.sh       # if tools need system-level install
#   ./scripts/03-pipx-tools.sh             # if installing for current user
#
# ===========================================================================

set -euo pipefail
# set -e  : Exit immediately if any command returns a non-zero status.
# set -u  : Treat unset variables as an error (catches typos in variable names).
# set -o pipefail : A pipeline fails if ANY command in it fails, not just the
#                   last one.  Without this, `bad_cmd | good_cmd` hides errors.

# ---------------------------------------------------------------------------
# Source the shared library
# ---------------------------------------------------------------------------
# "$(dirname "$0")" resolves to the directory containing THIS script, so
# lib.sh is found regardless of which directory you run the script from.
source "$(dirname "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Initialise logging and print the section header
# ---------------------------------------------------------------------------
setup_logging
print_header "Public pipx Tools"

# ---------------------------------------------------------------------------
# Verify pipx is available
# ---------------------------------------------------------------------------
# `command -v <name>` is how bash checks if a command exists on the system.
# It prints the path to the command (e.g. /usr/bin/pipx) and returns exit
# code 0 if found, or returns exit code 1 if the command does not exist.
#
# We prefer `command -v` over `which` because:
#   - `command` is a bash built-in (always available, no external dependency)
#   - `which` is an external program whose behaviour varies across distros
#   - `command -v` also finds shell functions and aliases, `which` may not
if ! command -v pipx &>/dev/null; then
    log_fail "PIPX" "pipx is not installed -- install it first (apt install pipx)"
    print_summary
    exit 1
fi

log_ok "PIPX" "pipx found at $(command -v pipx)"

# ---- Determine the real user ------------------------------------------------
# This script runs as root (via sudo), but pipx tools should be installed for
# the REAL user, not root.  If we ran `pipx install` as root, the tools would
# end up in /root/.local/bin instead of /home/brad/.local/bin.
#
# SUDO_USER is automatically set by sudo to the name of the user who invoked it.
# We use sudo -u to run pipx as that user.
REAL_USER="${SUDO_USER:-$USER}"

# Initialise this section so it appears in the summary table.
SECTION_RESULTS["PIPX"]="PASS"

# ---------------------------------------------------------------------------
# Locate the tools list
# ---------------------------------------------------------------------------
# REPO_DIR is set by lib.sh and points to the repository root directory.
TOOLS_FILE="${REPO_DIR}/lists/pipx-tools.txt"

if [[ ! -f "$TOOLS_FILE" ]]; then
    log_fail "PIPX" "Tools list not found: ${TOOLS_FILE}"
    print_summary
    exit 1
fi

# ---------------------------------------------------------------------------
# Read the file and install each tool
# ---------------------------------------------------------------------------
# Counters for the summary line at the end.
success_count=0
fail_count=0
skip_count=0

# `while IFS= read -r line` reads one line at a time from the file:
#   IFS=    : Prevents leading/trailing whitespace from being stripped.
#   -r      : Disables backslash interpretation (treats \ literally).
#   line    : The variable that receives each line's content.
#
# The `< "$TOOLS_FILE"` at the bottom of the loop redirects the file into
# the while loop's stdin, feeding it line by line.
while IFS= read -r line || [[ -n "$line" ]]; do

    # Strip inline comments: remove everything from ' #' onward.
    # This allows lines like "coercer  # NTLM relay helper".
    line="${line%%#*}"

    # Trim leading and trailing whitespace.  This uses bash pattern removal:
    #   ${var#pattern}  removes shortest match from the FRONT
    #   ${var%pattern}  removes shortest match from the END
    # The extra [[:space:]] handling covers tabs and spaces.
    line="$(echo "$line" | xargs)"

    # Skip empty lines (after stripping comments/whitespace, nothing remains).
    [[ -z "$line" ]] && continue

    # At this point, $line contains a clean tool name (e.g. "coercer").
    tool="$line"

    # Attempt the install using run_cmd from lib.sh.
    # run_cmd handles logging, output capture, and status reporting.
    #
    # We use `|| true` after run_cmd so that a failed install does not
    # trigger `set -e` and kill the entire script.  We want to continue
    # installing the remaining tools even if one fails.
    if run_cmd "PIPX" "Installing ${tool}" sudo -u "$REAL_USER" pipx install "$tool"; then
        success_count=$((success_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi

done < "$TOOLS_FILE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
# Calculate the total number of tools we processed.
total=$((success_count + fail_count + skip_count))

log_info "PIPX" "-------------------------------------------"
log_info "PIPX" "pipx install complete: ${success_count} succeeded, ${fail_count} failed (${total} total)"
log_info "PIPX" "-------------------------------------------"

# print_summary generates the full status table with per-section pass/fail,
# duration, failure list, and log file path.
print_summary
