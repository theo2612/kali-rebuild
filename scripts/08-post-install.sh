#!/usr/bin/env bash
# ===========================================================================
# 08-post-install.sh -- Post-install verification
# ===========================================================================
#
# This is the FINAL script in the kali-rebuild process.  It does NOT install
# anything.  Instead, it walks through everything the previous scripts should
# have set up and checks that each piece is actually present and working.
#
# Think of it as a "smoke test" for your rebuilt workstation.  It answers:
#   - Are all expected CLI tools on the PATH?
#   - Were the git-cloned tool directories created?
#   - Is Docker running?  Is BloodHound up?
#   - Are the dotfiles (zshrc, bashrc, gitconfig) in place?
#
# At the end it prints a summary of what passed and what failed, plus a
# list of manual steps that cannot be automated (e.g. license activation).
#
# USAGE:
#   ./scripts/08-post-install.sh          # run as the regular user
#   sudo ./scripts/08-post-install.sh     # also works (uses SUDO_USER)
#
# ---------------------------------------------------------------------------
# BASH CONCEPTS USED IN THIS SCRIPT
#
# command -v TOOL
#     A bash BUILT-IN that checks whether TOOL is available on the system.
#     If found, it prints the full path (e.g. /usr/bin/nmap) and returns
#     exit code 0.  If NOT found, it prints nothing and returns exit code 1.
#
#     We prefer `command -v` over `which` because:
#       - `command` is a shell built-in -- always available, zero overhead.
#       - `which` is an external program whose behaviour varies across distros.
#       - `command -v` also finds shell functions and aliases; `which` may not.
#
# &>/dev/null
#     Redirects BOTH stdout (file descriptor 1) AND stderr (file descriptor 2)
#     to /dev/null, which is a special "black hole" file that discards
#     everything written to it.  This silences ALL output from a command.
#
#     Breakdown:
#       &>   is shorthand for  >file 2>&1   (redirect stdout, then merge
#            stderr into stdout's destination).
#       /dev/null   is the discard device -- anything sent here disappears.
#
#     We use this pattern with `command -v` because we only care about the
#     EXIT CODE (0 = found, 1 = not found), not the printed path.
#
# Function definition: check_cmd() { ... }
#     Defining a function lets you write a block of code ONCE and call it
#     many times with different arguments.  This avoids copy-pasting the
#     same if/then/else pattern for every tool we want to verify.
#
#     Syntax:
#       function_name() {
#           local arg="$1"   # $1 is the first argument passed to the function
#           ...commands...
#       }
#
#     The "local" keyword restricts a variable to the function's scope so
#     it does not leak into or overwrite variables in the calling code.
#
# if/then/else
#     The fundamental branching construct in bash:
#       if CONDITION; then
#           ...commands run when CONDITION succeeds (exit code 0)...
#       else
#           ...commands run when CONDITION fails (non-zero exit code)...
#       fi
#
#     In bash, EVERYTHING is about exit codes.  The `if` does not test
#     "true" or "false" -- it runs a COMMAND and checks whether that
#     command returned exit code 0 (success) or non-zero (failure).
#
# Counting with arithmetic: (( count++ ))
#     (( )) is the arithmetic evaluation context.  Inside it, you can:
#       - Use C-style increment:  (( count++ ))
#       - Do math without $:     (( total = pass + fail ))
#       - Compare numbers:       (( count > 10 ))
#     Variables inside (( )) do NOT need the $ prefix (though it works
#     either way).
# ===========================================================================

# ---- Strict mode -----------------------------------------------------------
# -e : Exit immediately if ANY command returns a non-zero exit code.
# -u : Treat references to UNSET variables as an error.
# -o pipefail : A pipeline fails if ANY command in it fails, not just the last.
set -euo pipefail

# ---- Load the shared library -----------------------------------------------
# source (also written as ".") reads another file and executes it inside THIS
# shell.  After sourcing lib.sh we get access to log_info, log_ok, log_fail,
# run_cmd, print_header, print_summary, add_manual_step, etc.
#
# $(dirname "$0") expands to the directory containing THIS script (scripts/).
source "$(dirname "$0")/lib.sh"

# ---- Initialise logging ----------------------------------------------------
# setup_logging creates a timestamped log file and resets the timer that
# print_summary uses to show total duration.
setup_logging

# ---- Section name -----------------------------------------------------------
# All log lines and summary entries from this script use "VERIFY" as the
# section tag.
SECTION="VERIFY"

# Initialise this section in the results tracker.  It starts as PASS and
# flips to FAIL if any check does not pass.
SECTION_RESULTS["$SECTION"]="PASS"

# ---- Print header -----------------------------------------------------------
print_header "Post-Install Verification"

# ===========================================================================
# Determine the real (non-root) user and their home directory
# ===========================================================================
# When a script is run with `sudo`, the effective user is root, but the
# ORIGINAL user who typed "sudo" is stored in the environment variable
# SUDO_USER.  We need the real user so we can check paths like ~/tools/
# and ~/.zshrc that live in their home directory, not in /root.
#
# ${SUDO_USER:-$(whoami)} is a PARAMETER EXPANSION with a DEFAULT VALUE:
#   - If SUDO_USER is set and non-empty, use it.
#   - If SUDO_USER is unset or empty (i.e. not running under sudo), fall
#     back to $(whoami), which prints the current username.
#
# Look up the user's home directory from the system password database.
# getent passwd returns a colon-delimited record; field 6 is the home directory.
# This is safer than "eval echo ~user" and works consistently across all setups.
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

log_info "$SECTION" "Verifying installation for user: ${REAL_USER}"
log_info "$SECTION" "Home directory: ${REAL_HOME}"

# ===========================================================================
# HELPER FUNCTIONS
# ===========================================================================
# These small functions encapsulate the repetitive check-and-report pattern
# so we can verify many tools without duplicating code.

# ---- check_cmd TOOL_NAME ---------------------------------------------------
# Checks whether a command-line tool is available on the system PATH.
#
# How it works:
#   1. Takes one argument: the name of the tool to check (e.g. "nmap").
#   2. Runs `command -v` to look it up on the PATH.
#   3. If found (exit code 0): logs OK.
#   4. If not found (exit code 1): logs FAIL.
#
# The &>/dev/null silences the output of `command -v` because we only
# care about the exit code, not the path it prints.
#
# We use "local" to keep the variable scoped to this function so it does
# not collide with variables in the calling code.
check_cmd() {
    local tool="$1"

    # Check the system PATH first, then also check the user's ~/.local/bin
    # (where pipx installs tools).  When running under sudo, ~/.local/bin
    # is NOT on root's PATH, so command -v alone would miss pipx tools.
    if command -v "$tool" &>/dev/null; then
        log_ok "$SECTION" "${tool} found"
    elif [[ -x "${REAL_HOME}/.local/bin/${tool}" ]]; then
        log_ok "$SECTION" "${tool} found (in ~/.local/bin)"
    else
        log_fail "$SECTION" "${tool} NOT found"
    fi
}

# ---- check_dir DIR_PATH LABEL ----------------------------------------------
# Checks whether a directory exists on disk.
#
# How it works:
#   1. Takes two arguments: the full path and a human-friendly label.
#   2. Uses the [[ -d PATH ]] test -- the -d operator returns true if PATH
#      exists AND is a directory (not a file, not a symlink to a file).
#   3. Logs OK or FAIL accordingly.
#
# Why a separate function?
#   Without this, we would need to repeat the if/[[ -d ]]/then/else block
#   for every git-cloned tool directory we want to verify.  The function
#   lets us do it in one line per directory.
check_dir() {
    local dir_path="$1"
    local label="$2"

    if [[ -d "$dir_path" ]]; then
        log_ok "$SECTION" "${label} directory exists"
    else
        log_fail "$SECTION" "${label} directory NOT found: ${dir_path}"
    fi
}

# ---- check_file FILE_PATH LABEL --------------------------------------------
# Checks whether a file exists on disk.
#
# Similar to check_dir but uses [[ -f PATH ]] which tests for a REGULAR FILE
# (not a directory).  We use this for dotfiles like .zshrc and .bashrc.
check_file() {
    local file_path="$1"
    local label="$2"

    if [[ -f "$file_path" ]]; then
        log_ok "$SECTION" "${label} exists"
    else
        log_fail "$SECTION" "${label} NOT found: ${file_path}"
    fi
}


# ===========================================================================
# CHECK 1: APT-installed tools
# ===========================================================================
# These tools should have been installed by 02-apt-tools.sh via apt-get.
# We verify each one is on the PATH using our check_cmd helper.
#
# Why check_cmd instead of dpkg?
#   `dpkg -l package` tells you if a package is installed, but a package
#   might be installed without its binary being on the PATH (broken install).
#   `command -v` confirms the binary is actually findable and runnable.
log_info "$SECTION" "Checking APT-installed tools..."

# Each call to check_cmd tests one tool.  If the tool is missing, log_fail
# is called internally, which updates SECTION_RESULTS and the FAILURES array.
check_cmd "nmap"
check_cmd "hashcat"
check_cmd "john"
check_cmd "msfconsole"
check_cmd "wireshark"
check_cmd "sqlmap"
check_cmd "gobuster"
check_cmd "ffuf"
check_cmd "hydra"
check_cmd "nikto"
check_cmd "burpsuite"


# ===========================================================================
# CHECK 2: pipx-installed tools
# ===========================================================================
# These tools should have been installed by 03-pipx-tools.sh.  pipx places
# entry-point scripts in ~/.local/bin, which should be on the PATH after
# running `pipx ensurepath`.
log_info "$SECTION" "Checking pipx-installed tools..."

check_cmd "coercer"
check_cmd "adidnsdump"


# ===========================================================================
# CHECK 3: BLS (Black Lantern Security) tools
# ===========================================================================
# These tools should have been installed by 04-bls-tools.sh.  Some are pipx
# packages (installed from git+URL), others may be standalone binaries.
log_info "$SECTION" "Checking BLS tools..."

check_cmd "bbot"
check_cmd "secretsdump.py"
check_cmd "nxc"
check_cmd "certipy"
check_cmd "trevorspray"
check_cmd "pypykatz"
check_cmd "crackmapexec"


# ===========================================================================
# CHECK 4: Git-cloned tool directories
# ===========================================================================
# These tools should have been cloned by 05-git-tools.sh into ~/tools/.
# We check that each expected directory exists using our check_dir helper.
#
# Note: We use REAL_HOME (not ~) because:
#   - If running under sudo, ~ would expand to /root, not /home/brad.
#   - REAL_HOME was resolved above to the actual user's home directory.
log_info "$SECTION" "Checking git-cloned tool directories..."

check_dir "${REAL_HOME}/tools/CVE-2020-1472"   "CVE-2020-1472 (ZeroLogon)"
check_dir "${REAL_HOME}/tools/bloodyAD"         "bloodyAD"
check_dir "${REAL_HOME}/tools/beanshooter"      "beanshooter"
check_dir "${REAL_HOME}/tools/noPac"            "noPac"


# ===========================================================================
# CHECK 5: Docker and BloodHound
# ===========================================================================
# Docker should have been installed by 01-system-setup.sh, and BloodHound
# should have been set up by 06-docker-services.sh using docker compose.
log_info "$SECTION" "Checking Docker and BloodHound..."

# ---- Docker daemon ----------------------------------------------------------
# `systemctl is-active docker` prints "active" and returns 0 if the Docker
# daemon is running, or prints "inactive"/"failed" and returns non-zero if
# it is not.  run_cmd captures the output and reports OK/FAIL.
#
# We use `run_cmd` here (instead of check_cmd) because we are not looking
# for a binary on the PATH -- we are checking the STATUS of a running
# service, which is a different kind of check.
if run_cmd "$SECTION" "Docker daemon running" systemctl is-active docker; then
    # Only check BloodHound if Docker is actually running.  There is no
    # point checking docker compose services when the daemon is down.

    # ---- BloodHound docker compose -------------------------------------------
    # `docker compose -f FILE ps` lists containers defined in the compose file.
    # If BloodHound was set up correctly, this will show running containers
    # and return exit code 0.  If the file does not exist or the containers
    # are not running, it returns non-zero.
    #
    # We check for the compose file's existence first with [[ -f ]] to give
    # a more helpful error message than docker compose's generic error.
    if [[ -f "${REAL_HOME}/bloodhound/docker-compose.yml" ]]; then
        run_cmd "$SECTION" "BloodHound containers running" \
            docker compose -f "${REAL_HOME}/bloodhound/docker-compose.yml" ps || true
    else
        log_fail "$SECTION" "BloodHound docker-compose.yml not found at ${REAL_HOME}/bloodhound/"
    fi
else
    # Docker is not running, so skip the BloodHound check entirely.
    # log_skip records the skip with a yellow "SKIP" status badge.
    log_skip "$SECTION" "BloodHound container check" "Docker daemon is not running"
fi


# ===========================================================================
# CHECK 6: Configuration files (dotfiles)
# ===========================================================================
# These config files should have been deployed by 07-configs.sh.  We check
# that each one exists in the real user's home directory.
log_info "$SECTION" "Checking configuration files..."

check_file "${REAL_HOME}/.zshrc"     ".zshrc"
check_file "${REAL_HOME}/.bashrc"    ".bashrc"
check_file "${REAL_HOME}/.gitconfig" ".gitconfig"


# ===========================================================================
# COUNT RESULTS
# ===========================================================================
# The FAILURES array in lib.sh has been accumulating every failed check.
# We read its length to report a total pass/fail count.
#
# ${#FAILURES[@]} is parameter expansion that returns the NUMBER OF ELEMENTS
# in the FAILURES array.  The # prefix means "length of".
#   - ${#string}       -> length of string in characters
#   - ${#array[@]}     -> number of elements in array
total_failures=${#FAILURES[@]}

if (( total_failures == 0 )); then
    log_info "$SECTION" "All verification checks passed!"
else
    log_info "$SECTION" "${total_failures} verification check(s) failed -- review the list above"
fi


# ===========================================================================
# MANUAL STEPS
# ===========================================================================
# Some things simply cannot be automated.  They require a GUI, a login, or
# human judgement.  add_manual_step records these reminders so they are
# printed in the summary at the end, ensuring nothing is forgotten.
log_info "$SECTION" "Recording manual post-install steps..."

add_manual_step "Activate BurpSuite Professional license"
add_manual_step "Install Bitwarden extension in Firefox"
add_manual_step "Log into Signal Desktop"
add_manual_step "Generate SSH keys: ssh-keygen -t ed25519"
add_manual_step "Log out and back in for group changes to take effect"


# ===========================================================================
# SUMMARY
# ===========================================================================
# print_summary reads SECTION_RESULTS, FAILURES, and MANUAL_STEPS from lib.sh
# and outputs a formatted table showing:
#   - Each section with PASS or FAIL
#   - Total number of failures with details
#   - Manual steps remaining
#   - Total duration and log file path
print_summary
