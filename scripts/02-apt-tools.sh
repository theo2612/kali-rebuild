#!/usr/bin/env bash
# ===========================================================================
# 02-apt-tools.sh -- Install pentest tools from the APT package list
# ===========================================================================
#
# This script reads lists/apt-packages.txt and installs every package listed
# there using apt-get.  It is the second phase of the kali-rebuild process.
#
# USAGE (run as root or with sudo):
#   sudo ./scripts/02-apt-tools.sh
#
# The package list uses one package per line.  Lines starting with # are
# comments and blank lines are ignored.
#
# ---------------------------------------------------------------------------
# BASH CONCEPTS USED IN THIS SCRIPT
#
# set -euo pipefail  -- "strict mode" for bash:
#     -e  : exit immediately if a command fails (non-zero exit code)
#     -u  : treat unset variables as an error
#     -o pipefail : a pipeline fails if *any* command in it fails, not
#                   just the last one
#
# while IFS= read -r line  -- read a file line by line:
#     IFS=  : set the Internal Field Separator to empty so leading and
#             trailing whitespace is preserved (not stripped)
#     -r    : "raw" mode -- do not interpret backslash escape sequences
#             (e.g. \n stays as literal \n, not a newline)
#
# [[ "$line" =~ ^# ]]  -- regex matching in bash:
#     =~ is the regex match operator inside [[ ]].  ^# means "starts
#     with #".  This lets us detect comment lines.
#
# [[ -z "${line// /}" ]]  -- testing for empty/whitespace-only string:
#     -z returns true if the string has zero length.  ${line// /}
#     removes all spaces from the value before testing, so lines that
#     are only spaces are treated as empty too.
#
# continue  -- skip to the next iteration of the enclosing loop.
#     When we detect a comment or blank line, we "continue" to avoid
#     trying to install a non-existent package name.
#
# (( count++ ))  -- arithmetic in bash:
#     (( )) is the arithmetic evaluation context.  Inside it you can
#     use C-style increment (++), addition, subtraction, etc. without
#     needing the $ prefix on variable names.
#
# < "$file"  -- input redirection:
#     Feeds the contents of a file into the while-read loop's stdin
#     so that "read" pulls one line at a time from the file.
# ===========================================================================

set -euo pipefail

# ---- Source the shared library ---------------------------------------------
# dirname "$0" gives the directory of the currently running script.  We use
# it to locate lib.sh, which lives in the same scripts/ directory.
source "$(dirname "$0")/lib.sh"

# ---- Set up logging -------------------------------------------------------
# Creates the log file and starts the timer.  Must be called before any
# log_* or run_cmd calls.
setup_logging

# ---- Header ----------------------------------------------------------------
print_header "APT Pentest Tools"

# ---- Configuration ---------------------------------------------------------
# SECTION is the label that appears in log output and the summary table.
SECTION="APT"

# Initialise this section in the results tracker so it appears in the
# summary even if no packages are processed.
SECTION_RESULTS["$SECTION"]="PASS"

# PACKAGE_LIST points to the file containing one package name per line.
# REPO_DIR is set by lib.sh and points to the repository root.
PACKAGE_LIST="${REPO_DIR}/lists/apt-packages.txt"

# ---- Validate that the package list exists ---------------------------------
if [[ ! -f "$PACKAGE_LIST" ]]; then
    log_fail "$SECTION" "Package list not found: ${PACKAGE_LIST}"
    print_summary
    exit 1
fi

# ---- Update the package cache first ---------------------------------------
# Running apt-get update ensures we have the latest package metadata from
# all configured repositories.  -qq makes it almost silent.
run_cmd "$SECTION" "Updating package cache" apt-get update -qq

# ---- Read the package list and install each package -----------------------
# We track how many packages we successfully installed and how many failed
# so we can print a nice summary at the end.
success_count=0
fail_count=0
total_count=0

# while IFS= read -r line -- read one line at a time from the package list.
#   IFS=   : do not split on whitespace (preserve the whole line)
#   -r     : raw mode -- no backslash interpretation
#   || [[ -n "$line" ]]  : handle files that don't end with a newline;
#                          without this, the last line would be skipped
#                          if there is no trailing newline character.
while IFS= read -r line || [[ -n "$line" ]]; do

    # ---- Strip inline comments and trim whitespace -------------------------
    # Remove everything from the first # onward (inline comments).
    # Then trim leading and trailing whitespace.
    line="${line%%#*}"

    # [[ -z "${line// /}" ]] -- test for empty/whitespace-only string.
    # ${line// /} removes all spaces.  If nothing remains, skip the line.
    # We also handle tabs by first converting them to spaces.
    # Replace tabs with spaces first, then check if anything remains.
    local_trimmed="${line//$'\t'/ }"
    if [[ -z "${local_trimmed// /}" ]]; then
        # Blank line or comment-only line -- skip to the next iteration.
        continue
    fi

    # ---- Extract the package name ------------------------------------------
    # Trim leading and trailing whitespace from the line.  We use xargs as a
    # simple trick: it strips surrounding whitespace by default.
    package="$(echo "$line" | xargs)"

    # Double-check: skip if somehow still empty after trimming.
    if [[ -z "$package" ]]; then
        continue
    fi

    # ---- Install the package -----------------------------------------------
    # (( total_count++ )) -- arithmetic increment.  Counts every package we
    # attempt to install.
    (( total_count++ ))

    # run_cmd runs the command, logs output, and shows OK or FAIL on screen.
    # The -y flag auto-confirms prompts so the script runs unattended.
    # The -qq flag makes apt-get quiet -- less noise in the log file.
    #
    # We use "|| true" to prevent set -e from killing the whole script when
    # a single package fails.  Instead we capture the failure and keep going.
    if run_cmd "$SECTION" "Installing ${package}" apt-get install -y -qq "$package"; then
        # (( success_count++ )) -- the install succeeded, bump the counter.
        (( success_count++ ))
    else
        # (( fail_count++ )) -- the install failed, bump the failure counter.
        (( fail_count++ ))
    fi

done < "$PACKAGE_LIST"

# ---- Summary ---------------------------------------------------------------
# Log a one-line summary showing how many packages were installed vs failed.
log_info "$SECTION" "Installed ${success_count} packages (${fail_count} failed)"

# ---- Print the overall summary table and exit ------------------------------
print_summary
