#!/usr/bin/env bash
# ===========================================================================
# install.sh -- Main orchestrator for kali-rebuild
# ===========================================================================
#
# This is the ONE script you run after a fresh Kali install:
#
#   git clone <your-repo-url> ~/kali-rebuild
#   cd ~/kali-rebuild
#   sudo ./install.sh
#
# It calls each numbered script (01 through 08) in order, checks exit codes,
# and presents a final pass/fail summary at the end.
#
# WHY AN ORCHESTRATOR?
# --------------------
# You could run each script manually, but this file:
#   1. Guarantees the correct execution order
#   2. Checks every exit code and asks you whether to continue on failure
#   3. Provides a single combined summary of the entire rebuild process
#   4. Handles the root check so you cannot accidentally run as a normal user
#
# ---------------------------------------------------------------------------
# BASH CONCEPTS USED IN THIS SCRIPT
#
# $EUID  (Effective User ID)
#     Every Unix process runs as a user.  The "effective" UID determines what
#     permissions the process actually has.  UID 0 is always root.  We check
#     $EUID (rather than $UID) because sudo changes the effective UID to 0
#     while leaving the real UID unchanged.  $EUID is a bash built-in; you
#     do not need to call any external program to read it.
#
# exec
#     exec REPLACES the current process with a new one.  It does NOT start a
#     child process -- the current shell literally becomes the new command.
#     The original process ceases to exist, so no code after "exec" runs.
#
#     We use it here to re-run this script under sudo.  Without exec, the
#     non-root shell would sit idle waiting for the sudo'd child to finish.
#     With exec, there is only ever one copy of the script running.
#
# "$@" (all arguments)
#     "$@" expands to every positional parameter passed to the script, each
#     one individually quoted.  This preserves arguments that contain spaces.
#
#     Example:  ./install.sh --skip "step 3"
#       "$@"  ->  "--skip" "step 3"   (two separate arguments, correct)
#       $@    ->  "--skip" "step" "3" (three arguments, WRONG -- word splitting)
#
#     We pass "$@" through to the exec sudo call so any arguments the user
#     provided on the command line are forwarded to the re-invoked script.
#
# BASH_SOURCE[0] vs $0
#     $0 is the name of the script as invoked on the command line:
#       bash install.sh         -> $0 = "install.sh"
#       ./install.sh            -> $0 = "./install.sh"
#       source install.sh       -> $0 = "-bash" (the sourcing shell's name!)
#
#     BASH_SOURCE[0] is ALWAYS the path of the file currently being executed
#     or sourced, regardless of how it was invoked.  This makes it the
#     reliable way to find a script's own location on disk.
#
#     We use BASH_SOURCE[0] to derive SCRIPT_DIR -- the absolute path of the
#     directory containing this file -- so we can locate the scripts/ folder
#     even when the user runs install.sh from a different working directory.
#
# Subprocesses vs sourcing
#     "source script.sh" (or ". script.sh") runs the script INSIDE the
#     current shell.  All variables, functions, and settings are shared.
#     If the sourced script calls "exit", YOUR shell exits too.
#
#     "bash script.sh" runs the script as a CHILD PROCESS (subprocess).
#     It gets its own copy of the environment.  If it calls "exit", only
#     the child dies -- your shell continues.  Variables set in the child
#     do NOT propagate back to the parent.
#
#     In this orchestrator we use BOTH approaches:
#       - We SOURCE lib.sh because we need its functions (log_info, log_ok,
#         log_fail, print_summary, etc.) available in our own shell.
#       - We run each numbered script as a SUBPROCESS (bash script.sh)
#         because each script manages its own logging, strict mode, and
#         summary independently.  If a script fails or exits, the
#         orchestrator stays alive to report the failure and continue.
#
# Function definitions
#     function_name() { ... } defines a reusable block of code.  Once
#     defined, you call it by name like any other command:
#       run_script "01-system-setup.sh" "System Setup"
#
#     Functions have access to their own positional parameters ($1, $2, ...),
#     separate from the script's positional parameters.  Using "local"
#     inside a function restricts variables to the function scope.
#
# set -euo pipefail ("strict mode")
#     -e  : Exit immediately if ANY command returns a non-zero exit code.
#     -u  : Treat references to UNSET variables as an error.
#     -o pipefail : In a pipeline (cmd1 | cmd2), the pipeline's exit code
#                   is the last NON-ZERO code from any command in the pipe.
#                   Without this, only the exit code of the LAST command is
#                   reported.
# ===========================================================================

# ===========================================================================
# STEP 1: Root check
# ===========================================================================
# We need root privileges because the install scripts:
#   - Install packages with apt-get (requires root)
#   - Write to /etc/apt/sources.list.d/ (requires root)
#   - Manage Docker (requires root or group membership)
#   - Copy files into system directories (requires root)
#
# If the user forgets "sudo", we helpfully re-execute under sudo rather
# than printing an error and quitting.
#
# NOTE: We do this BEFORE set -e so that the exec does not trigger an
# error exit in edge cases (e.g. if sudo prompts and the user cancels).
# ===========================================================================
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

# ===========================================================================
# STEP 2: Determine script location
# ===========================================================================
# SCRIPT_DIR is the absolute path to the directory containing this file.
#
# Breakdown of the command:
#   ${BASH_SOURCE[0]}             -- the path to THIS file (install.sh)
#   dirname "${BASH_SOURCE[0]}"   -- strip the filename, leaving the directory
#   cd "..." && pwd               -- cd into that directory and print the
#                                    absolute path.  cd resolves symlinks and
#                                    relative paths; pwd then gives us a clean
#                                    absolute path.
#
# We wrap this in $(...) (command substitution) to capture the output of pwd
# into the SCRIPT_DIR variable.
#
# Why not just use dirname alone?  Because dirname might return a relative
# path like "." or "../kali-rebuild".  The cd && pwd combination guarantees
# an absolute path regardless of how the script was invoked.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_DIR is the same as SCRIPT_DIR for install.sh because this script
# lives at the root of the repository.  lib.sh also sets REPO_DIR (relative
# to its own location in scripts/), but we set it here too so it is available
# before we source lib.sh, and as an export so child processes inherit it.
#
# export makes the variable available to child processes.  Without export,
# only the current shell can see the variable.  The numbered scripts run as
# child processes (via "bash script.sh"), so they need REPO_DIR exported.
export REPO_DIR="$SCRIPT_DIR"

# ===========================================================================
# STEP 3: Strict mode
# ===========================================================================
# Normally we set strict mode at the very top of a script, but in this case
# we did the root check first (Step 1) because:
#   - The root check uses "exec" which replaces the process entirely
#   - We wanted that to happen cleanly without strict mode interference
#
# From this point on, strict mode protects us:
#   -e         : Exit on any error (we manage this carefully with if-blocks
#                around subprocess calls so a single script failure does not
#                kill the entire orchestrator)
#   -u         : Catch typos in variable names immediately
#   -o pipefail: Catch failures hidden inside pipelines
set -euo pipefail

# ===========================================================================
# STEP 4: Source the shared library
# ===========================================================================
# We SOURCE lib.sh (not "bash lib.sh") because we need its functions --
# log_info, log_ok, log_fail, ask_continue, print_summary, etc. -- to be
# available in THIS shell.  If we ran it as a subprocess, the functions
# would only exist in the child and disappear when it exited.
#
# lib.sh lives in the scripts/ subdirectory.
source "${SCRIPT_DIR}/scripts/lib.sh"

# ===========================================================================
# STEP 5: Set up logging
# ===========================================================================
# setup_logging (defined in lib.sh) creates a timestamped log file under
# logs/ and resets the SECONDS counter for timing.  The orchestrator gets
# its own log file, separate from the log files each sub-script creates.
setup_logging

# ---- Section name for orchestrator logging --------------------------------
# All log lines emitted by this script use "MAIN" as the section tag.
SECTION="MAIN"

# Initialise MAIN in the results tracker so it appears in the summary table.
SECTION_RESULTS["$SECTION"]="PASS"

# ===========================================================================
# STEP 6: Set TOTAL_STEPS
# ===========================================================================
# lib.sh uses TOTAL_STEPS in print_header to show "Step N of 8".  If this
# variable is not set, print_header just shows "Step N" without a total.
# Setting it here gives the user a sense of overall progress.
TOTAL_STEPS=8

# ===========================================================================
# STEP 7: Welcome banner
# ===========================================================================
# Print a visual banner so the user knows the rebuild process has started.
# We use Unicode box-drawing characters (╔ ═ ╗ ║ ╚ ╝) for a clean look.
#
# echo "" prints a blank line for visual spacing.  printf could also be used,
# but echo is simpler for plain text with no formatting requirements.
#
# The -e flag on echo enables interpretation of escape sequences like \e[1m
# (bold) and \e[0m (reset).  Without -e, those codes would print literally.
echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "  ${BOLD}║                                          ║${RESET}"
echo -e "  ${BOLD}║        KALI REBUILD SYSTEM               ║${RESET}"
echo -e "  ${BOLD}║   Automated Pentest Workstation Setup    ║${RESET}"
echo -e "  ${BOLD}║                                          ║${RESET}"
echo -e "  ${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""

# Show the user where log output is going.  The LOGFILE variable was set
# by setup_logging and contains the full path (e.g. logs/install-20260215-143022.log).
log_info "$SECTION" "Orchestrator log: ${LOGFILE}"
log_info "$SECTION" "Each sub-script also creates its own log in logs/"
echo ""

# ===========================================================================
# STEP 8: Define the run_script helper function
# ===========================================================================
# run_script wraps the logic for executing one numbered sub-script.  Without
# this function, we would have to repeat the same bash/if/log_ok/log_fail
# pattern eight times -- once for each script.  The function takes two
# arguments:
#
#   $1 -- the script filename (e.g. "01-system-setup.sh")
#   $2 -- a human-readable name for log messages (e.g. "System Setup")
#
# HOW IT WORKS:
#   1. Constructs the full path to the script using SCRIPT_DIR.
#   2. Checks that the script file actually exists (defensive programming).
#   3. Runs the script as a SUBPROCESS using "bash".  This is important:
#      each script has its own "set -euo pipefail", its own setup_logging,
#      and its own print_summary.  Running as a subprocess keeps all of that
#      isolated from the orchestrator.
#   4. Checks the exit code ($?):
#      - Exit code 0 means success -> log_ok
#      - Non-zero means failure    -> log_fail, then ask the user whether
#        to continue or abort using ask_continue (defined in lib.sh).
#
# NOTE ON set -e INTERACTION:
#   Normally, set -e would cause the orchestrator to exit immediately if
#   "bash script.sh" returns non-zero.  However, when a command appears as
#   the condition of an "if" statement, set -e does NOT apply to it.  This
#   is a specific rule in the bash manual.  So:
#     if bash script.sh; then ...    # set -e is SUPPRESSED for this command
#     bash script.sh                  # set -e WOULD kill us on failure
#   We intentionally use the if-form to stay alive after a script failure.
# ---------------------------------------------------------------------------
run_script() {
    local script="$1"
    local name="$2"
    local script_path="${SCRIPT_DIR}/scripts/${script}"

    # ---- Verify the script file exists ------------------------------------
    # [[ -f "$path" ]] tests if the path is a regular file.  If someone
    # deleted or renamed a script, we catch it here instead of getting a
    # confusing "No such file" error from bash.
    if [[ ! -f "$script_path" ]]; then
        log_fail "$SECTION" "${name} -- script not found: ${script_path}"
        ask_continue
        return
    fi

    log_info "$SECTION" "Running ${name}..."

    # ---- Execute the sub-script as a subprocess ---------------------------
    # "bash" starts a new shell process.  The sub-script runs in that child
    # shell with its own environment.  When it finishes:
    #   - exit 0 -> the if-condition is TRUE  -> log_ok
    #   - exit N -> the if-condition is FALSE  -> log_fail + ask_continue
    #
    # Because this is inside an "if", set -e does not trigger even if the
    # sub-script returns non-zero.  This is by design -- we WANT to keep
    # running so we can ask the user what to do next.
    if bash "$script_path"; then
        log_ok "$SECTION" "${name} completed successfully"
    else
        log_fail "$SECTION" "${name} FAILED (see its own log for details)"
        ask_continue
    fi
}

# ===========================================================================
# STEP 9: Run each install script in order
# ===========================================================================
# The scripts MUST run in this order because later scripts depend on what
# earlier scripts installed:
#
#   01 -- System Setup:       Adds repos, signing keys, base packages.
#                              Everything else needs git, curl, docker, etc.
#
#   02 -- APT Pentest Tools:  Installs tools from apt.  Must come after 01
#                              because 01 adds third-party repos that some
#                              of these tools come from.
#
#   03 -- pipx Tools:         Installs Python tools in isolated envs.  Needs
#                              pipx, which was installed in 01.
#
#   04 -- BLS Fork Tools:     Installs BLS (Black Lantern Security) forks via
#                              pipx.  Same dependency on pipx from 01.
#
#   05 -- Git-Clone Tools:    Clones tool repos into ~/tools/.  Needs git
#                              from 01.
#
#   06 -- Docker Services:    Sets up BloodHound and other containers.  Needs
#                              Docker from 01.
#
#   07 -- Configs & Dotfiles: Installs the dotfiles repo into ~/ and
#                              XFCE display/font settings.
#                              Runs late so it does not get overwritten by
#                              package installs.
#
#   08 -- Post-Install:       Verification only -- checks that everything
#                              from 01-07 was installed correctly.  Must be
#                              LAST because it tests the work of all others.
# ---------------------------------------------------------------------------

# print_header (from lib.sh) outputs a prominent banner with an auto-
# incrementing step counter.  We call it before each run_script so the
# user can see which phase they are in.

print_header "System Setup"
run_script "01-system-setup.sh" "System Setup"

print_header "APT Pentest Tools"
run_script "02-apt-tools.sh" "APT Pentest Tools"

print_header "Public pipx Tools"
run_script "03-pipx-tools.sh" "Public pipx Tools"

print_header "BLS Fork Tools"
run_script "04-bls-tools.sh" "BLS Fork Tools"

print_header "Git-Clone Tools"
run_script "05-git-tools.sh" "Git-Clone Tools"

print_header "Docker Services"
run_script "06-docker-services.sh" "Docker Services"

print_header "Configs & Dotfiles"
run_script "07-configs.sh" "Configs & Dotfiles"

print_header "Post-Install Verification"
run_script "08-post-install.sh" "Post-Install Verification"

# ===========================================================================
# STEP 10: Print the final summary
# ===========================================================================
# print_summary (from lib.sh) reads the SECTION_RESULTS associative array
# and the FAILURES indexed array that have been built up by our log_ok and
# log_fail calls throughout this script.  It outputs:
#   - A table of each section with PASS or FAIL
#   - A count and list of failures (if any)
#   - Any manual steps recorded with add_manual_step
#   - Total duration (from the SECONDS counter reset in setup_logging)
#   - The path to the orchestrator's log file
print_summary

# ===========================================================================
# STEP 11: Closing message with next steps
# ===========================================================================
# After the summary table, give the user clear guidance on what to do next.
# This is especially important for things that could not be automated.
echo -e "  ${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "  ${BOLD}║           REBUILD COMPLETE               ║${RESET}"
echo -e "  ${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo "  Next steps:"
echo ""
echo "    1. Review the summary above for any FAIL items"
echo "    2. Check individual script logs in: ${REPO_DIR}/logs/"
echo "    3. Complete any manual steps listed above"
echo "    4. Log out and back in for group changes (e.g. docker) to take effect"
echo "    5. Reboot if a kernel or driver update was installed"
echo ""
echo "  To re-run a single phase, execute the script directly:"
echo "    sudo bash ${SCRIPT_DIR}/scripts/01-system-setup.sh"
echo ""
echo -e "  ${GREEN}${BOLD}Happy hacking!${RESET}"
echo ""
