#!/usr/bin/env bash
# ===========================================================================
# lib.sh -- Shared logging and utility library for kali-rebuild
# ===========================================================================
#
# This file is the foundation every install script sources.  It provides:
#   - Colourised, column-aligned screen output
#   - Timestamped log file writing (verbose command output goes to the log)
#   - A summary system that tracks pass/fail per section
#   - Helper functions like run_cmd (run a command, log it, report status)
#
# HOW TO USE:
#   source "$(dirname "$0")/lib.sh"    # from any script in scripts/
#   setup_logging                       # call once at the top of your script
#   run_cmd "APT" "Update package cache" apt-get update -qq
#   print_summary                       # call once at the end
#
# ---------------------------------------------------------------------------
# BASH CONCEPTS USED IN THIS FILE
#
# local variables  -- "local" restricts a variable to the function scope so
#                     it does not leak into the caller's environment.
# arrays           -- FAILURES=() creates an indexed array.  += appends.
# assoc arrays     -- declare -A creates an associative (key/value) array.
#                     Used here for per-section pass/fail tracking.
# exit codes       -- Every command returns 0 on success, non-zero on failure.
#                     We capture this in $? and use it to decide OK vs FAIL.
# redirects        -- >> appends to a file.  2>&1 merges stderr into stdout.
#                     We send verbose output to the log while keeping the
#                     screen output clean.
# ANSI colours     -- Special escape sequences (\e[32m etc.) tell the terminal
#                     to change text colour.  We reset with \e[0m.
# BASH_SOURCE[0]   -- The path of the file currently being executed or sourced.
#                     Comparing it to $0 lets us detect whether the file was
#                     sourced (correct) or run directly (incorrect).
# SECONDS          -- A built-in bash variable that counts seconds since the
#                     shell started (or since you set it to 0).
# printf vs echo   -- printf gives us precise control over field widths and
#                     formatting.  We use it for column-aligned output.
# ===========================================================================

# ---- Source guard ----------------------------------------------------------
# This file is meant to be sourced, not executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    echo "Usage: source scripts/lib.sh"
    exit 1
fi

# ---- Repository root directory ---------------------------------------------
# REPO_DIR is the top-level directory of the repository.  We derive it from
# the location of this file (scripts/lib.sh -> parent is scripts/ -> parent
# is the repo root).  Other scripts use REPO_DIR to locate list files,
# configs, and other resources.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- Colour setup ----------------------------------------------------------
# ANSI escape codes for coloured terminal output.  We only enable colours
# when stdout is connected to a terminal (not piped to a file).  The test
# [[ -t 1 ]] checks file descriptor 1 (stdout).
if [[ -t 1 ]]; then
    GREEN=$'\e[32m'
    RED=$'\e[31m'
    YELLOW=$'\e[33m'
    BOLD=$'\e[1m'
    RESET=$'\e[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    BOLD=''
    RESET=''
fi

# ---- Global state ----------------------------------------------------------
# FAILURES is an indexed array that collects "section: message" strings each
# time something fails.  print_summary reads it at the end.
FAILURES=()

# SECTION_RESULTS is an associative array mapping section names to their
# status ("PASS" or "FAIL").  Every section starts as PASS and flips to FAIL
# on the first failure.  declare -A creates an associative array.
declare -A SECTION_RESULTS

# MANUAL_STEPS collects reminders for things the user has to do by hand after
# the automated install finishes (e.g. "Log out and back in for group changes").
MANUAL_STEPS=()

# LOGFILE will be set by setup_logging.  We initialise it here so that the
# log_* functions can check whether logging has been set up.
LOGFILE=""

# ---- setup_logging ---------------------------------------------------------
# Call this once at the start of your script.  It:
#   1. Creates the logs/ directory if needed
#   2. Creates a timestamped log file
#   3. Records the start time so print_summary can show total duration
#   4. Writes a header to the log file
setup_logging() {
    local log_dir="${REPO_DIR}/logs"

    # Create the logs directory if it does not exist.  -p means "no error if
    # it already exists, and create parent directories as needed."
    mkdir -p "$log_dir"

    # Build a log filename with the current date and time.
    # Example: install-20260215-143022.log
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    LOGFILE="${log_dir}/install-${timestamp}.log"

    # Reset the built-in SECONDS counter.  We read it later in print_summary
    # to calculate how long the whole run took.
    SECONDS=0

    # Write a header into the log file so it is easy to identify later.
    {
        echo "========================================"
        echo "kali-rebuild log -- $(date)"
        echo "========================================"
        echo ""
    } >> "$LOGFILE"

    log_info "INIT" "Log file: ${LOGFILE}"
}

# ---- _write_log (internal helper) -----------------------------------------
# Appends a timestamped line to the log file.  The leading underscore is a
# convention meaning "private / internal -- not meant to be called directly."
_write_log() {
    local level="$1"   # e.g. INFO, OK, FAIL, SKIP
    local section="$2"
    local message="$3"

    # Guard: if setup_logging has not been called yet, silently skip.
    [[ -z "$LOGFILE" ]] && return 0

    # date '+%H:%M:%S' gives the current time.  We prefix every log line with
    # the time, level, and section so the log file is easy to search.
    printf '%s  %-5s  [%-12s]  %s\n' \
        "$(date '+%H:%M:%S')" "$level" "$section" "$message" >> "$LOGFILE"
}

# ---- log_info SECTION MESSAGE ----------------------------------------------
# Prints an informational line to the screen (no status suffix) and writes
# it to the log file.  Use this for progress messages that do not represent
# a pass/fail outcome.
log_info() {
    local section="$1"
    local message="$2"

    printf "  ${BOLD}[%s]${RESET}  %s\n" "$section" "$message"
    _write_log "INFO" "$section" "$message"
}

# ---- log_ok SECTION MESSAGE ------------------------------------------------
# Prints a line with a green "OK" right-aligned at a fixed column, then
# writes to the log.  Use this when an action succeeded.
log_ok() {
    local section="$1"
    local message="$2"

    # %-55s left-aligns the message in a 55-character-wide field.  This pushes
    # the status badge to a consistent column so the output looks like a table.
    printf "  %-55s ${GREEN}OK${RESET}\n" "[${section}]  ${message}"
    _write_log "OK" "$section" "$message"
}

# ---- log_fail SECTION MESSAGE ----------------------------------------------
# Prints a line with a red "FAIL" status, records the failure in the FAILURES
# array, and marks the section as failed in SECTION_RESULTS.
log_fail() {
    local section="$1"
    local message="$2"

    printf "  %-55s ${RED}FAIL${RESET}\n" "[${section}]  ${message}"
    _write_log "FAIL" "$section" "$message"

    # Record the failure for the summary.  += appends to an indexed array.
    FAILURES+=("${section}: ${message}")

    # Mark this section as FAIL.  Even if later commands in the same section
    # succeed, the section stays FAIL because at least one thing broke.
    SECTION_RESULTS["$section"]="FAIL"
}

# ---- log_skip SECTION MESSAGE REASON --------------------------------------
# Prints a line with a yellow "SKIP" status.  Used when something is
# intentionally skipped (e.g. a package is already installed).
log_skip() {
    local section="$1"
    local message="$2"
    local reason="${3:-}"  # optional; default to empty string

    local display="${message}"
    [[ -n "$reason" ]] && display="${message} (${reason})"

    printf "  %-55s ${YELLOW}SKIP${RESET}\n" "[${section}]  ${display}"
    _write_log "SKIP" "$section" "$display"
}

# ---- run_cmd SECTION MESSAGE COMMAND... ------------------------------------
# The workhorse function.  Most install steps look like:
#
#   run_cmd "APT" "Install vim" apt-get install -y vim
#
# It:
#   1. Prints "[SECTION]  MESSAGE..." to the screen
#   2. Runs COMMAND, capturing stdout+stderr to the log file
#   3. Shows green OK on success or red FAIL on failure
#   4. Returns the command's exit code so callers can react
#
# IMPORTANT: The command and its arguments are everything after the second
# positional parameter.  We use "${@:3}" which means "all arguments from
# position 3 onward."  This lets you pass commands with flags naturally.
run_cmd() {
    local section="$1"
    local message="$2"
    shift 2  # Remove section and message; $@ now contains just the command

    # Make sure the section has an entry in SECTION_RESULTS.  If it is the
    # first command in this section, default to PASS (it may flip to FAIL).
    if [[ -z "${SECTION_RESULTS[$section]+x}" ]]; then
        SECTION_RESULTS["$section"]="PASS"
    fi

    # Log the command we are about to run (useful for debugging).
    _write_log "RUN" "$section" "$message -- $*"

    # Run the command.  We capture all output (stdout and stderr, via 2>&1)
    # and append it to the log file.  The screen stays clean.
    local exit_code
    "$@" >> "$LOGFILE" 2>&1
    exit_code=$?

    # Report result based on exit code.
    if [[ $exit_code -eq 0 ]]; then
        log_ok "$section" "$message"
    else
        log_fail "$section" "$message"
        _write_log "ERR" "$section" "Command exited with code ${exit_code}: $*"
    fi

    # Return the original exit code so the caller can check it with $? or
    # use it in an if-statement.
    return $exit_code
}

# ---- print_header TITLE ----------------------------------------------------
# Prints a prominent section header to visually separate phases of the install.
# The STEP_COUNTER auto-increments so you don't have to track numbers manually.
#
# Usage:
#   print_header "System Setup"
#   # prints: === [Step 1 of N] System Setup ===
#
# If TOTAL_STEPS is not set by the calling script, headers will just show
# the step number without "of N".
STEP_COUNTER=0

print_header() {
    local title="$1"
    STEP_COUNTER=$((STEP_COUNTER + 1))

    local step_label
    if [[ -n "${TOTAL_STEPS:-}" ]]; then
        step_label="Step ${STEP_COUNTER} of ${TOTAL_STEPS}"
    else
        step_label="Step ${STEP_COUNTER}"
    fi

    echo ""
    printf "  ${BOLD}=== [%s] %s ===${RESET}\n" "$step_label" "$title"
    echo ""

    _write_log "HEAD" "$title" "--- ${step_label} ---"
}

# ---- add_manual_step MESSAGE -----------------------------------------------
# Records a reminder that will be shown in the summary.  Use this for things
# the user must do by hand (reboot, log out, open a GUI, etc.).
add_manual_step() {
    MANUAL_STEPS+=("$1")
}

# ---- print_summary ---------------------------------------------------------
# Prints the end-of-run summary table.  Call this once at the very end of
# your install script.  It shows:
#   - Each section with PASS or FAIL
#   - Total number of failures
#   - Total duration
#   - Manual steps remaining
#   - Path to the log file
print_summary() {
    # Calculate how long the run took using the SECONDS variable that was
    # reset in setup_logging.
    local duration=$SECONDS
    local mins=$((duration / 60))
    local secs=$((duration % 60))

    echo ""
    echo "  ${BOLD}========================================${RESET}"
    echo "  ${BOLD}           INSTALL SUMMARY${RESET}"
    echo "  ${BOLD}========================================${RESET}"
    echo ""

    # Section results table.  Loop over the keys of the associative array.
    # "${!SECTION_RESULTS[@]}" expands to all keys.
    if [[ ${#SECTION_RESULTS[@]} -gt 0 ]]; then
        printf "  ${BOLD}%-25s %s${RESET}\n" "Section" "Result"
        printf "  %-25s %s\n" "-------------------------" "------"

        local section
        for section in "${!SECTION_RESULTS[@]}"; do
            local result="${SECTION_RESULTS[$section]}"
            if [[ "$result" == "PASS" ]]; then
                printf "  %-25s ${GREEN}%s${RESET}\n" "$section" "PASS"
            else
                printf "  %-25s ${RED}%s${RESET}\n" "$section" "FAIL"
            fi
        done
        echo ""
    fi

    # Failure count and list.
    local fail_count=${#FAILURES[@]}
    if [[ $fail_count -eq 0 ]]; then
        printf "  ${GREEN}${BOLD}All steps completed successfully.${RESET}\n"
    else
        printf "  ${RED}${BOLD}%d failure(s):${RESET}\n" "$fail_count"
        local f
        for f in "${FAILURES[@]}"; do
            printf "    ${RED}- %s${RESET}\n" "$f"
        done
    fi
    echo ""

    # Manual steps.
    if [[ ${#MANUAL_STEPS[@]} -gt 0 ]]; then
        printf "  ${BOLD}Manual steps remaining:${RESET}\n"
        local step
        for step in "${MANUAL_STEPS[@]}"; do
            printf "    ${YELLOW}- %s${RESET}\n" "$step"
        done
        echo ""
    fi

    # Duration and log path.
    printf "  Duration : %dm %ds\n" "$mins" "$secs"
    printf "  Log file : %s\n" "$LOGFILE"
    echo ""
    echo "  ${BOLD}========================================${RESET}"
    echo ""

    # Exit status reflects whether anything failed.  print_summary is the
    # last command in every sub-script, so this becomes the script's exit
    # code -- which is what install.sh checks.  Without this, a script with
    # failed items would still exit 0 and install.sh would report the whole
    # step as "completed successfully".
    (( fail_count == 0 ))
}

# ---- ask_continue ----------------------------------------------------------
# Called after a failure to let the user decide whether to keep going or stop.
# Reads a single character: "c" to continue, "a" to abort.
#
# If stdin is not a terminal (e.g. running non-interactively), we default to
# continue so automated runs don't hang waiting for input.
ask_continue() {
    # If stdin is not a terminal, skip the prompt and continue automatically.
    if [[ ! -t 0 ]]; then
        _write_log "INFO" "PROMPT" "Non-interactive mode -- continuing after failure"
        return 0
    fi

    local choice
    while true; do
        printf "\n  ${YELLOW}${BOLD}Continue to next item or abort? [c/a]:${RESET} "
        read -r -n 1 choice
        echo ""  # move to next line after the single character

        case "$choice" in
            c|C)
                _write_log "INFO" "PROMPT" "User chose to continue"
                return 0
                ;;
            a|A)
                _write_log "INFO" "PROMPT" "User chose to abort"
                echo "  Aborting."
                exit 1
                ;;
            *)
                echo "  Please press 'c' to continue or 'a' to abort."
                ;;
        esac
    done
}
