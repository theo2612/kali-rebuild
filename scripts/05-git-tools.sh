#!/usr/bin/env bash
# ===========================================================================
# 05-git-tools.sh -- Clone standalone pentest tools from GitHub
# ===========================================================================
#
# This script clones a curated list of security-research repositories into
# the ~/tools/ directory.  These are tools that are NOT distributed through
# pip/pipx or apt -- they are standalone projects you run directly from their
# cloned source tree (Python scripts, Java JARs, exploit PoCs, etc.).
#
# IDEMPOTENCY
# -----------
# Running this script multiple times is safe.  Before every git-clone it
# checks whether the target directory already exists and skips the clone if
# so.  This means you can re-run the full kali-rebuild without re-downloading
# tools you already have.
#
# RUNNING AS ROOT
# ---------------
# install.sh calls this script with sudo so it has permission to install
# system-wide dependencies.  However, we want the cloned tool directories to
# be owned by the real (non-root) user, not root.  We use the SUDO_USER
# environment variable (explained below) together with `sudo -u` to run the
# git-clone as the original user.
#
# BASH CONCEPTS COVERED
# ---------------------
#   SUDO_USER      -- When you run `sudo ./script.sh`, bash sets two user
#                     identities:
#                       $USER       = "root"  (the effective user)
#                       $SUDO_USER  = "brad"  (the REAL user who typed sudo)
#                     We use SUDO_USER to find the real user's home directory
#                     and to run git-clone as that user so the files are not
#                     owned by root.
#
#   Parallel arrays -- Bash does not have arrays-of-structs or dictionaries
#                      with multiple values per key.  A common workaround is
#                      to use two (or more) indexed arrays where the same
#                      index i refers to related data:
#                        TOOL_NAMES[0]="CVE-2020-1472"
#                        TOOL_URLS[0]="https://github.com/..."
#                      You loop with a numeric index to access both arrays
#                      in lockstep.  This is called "parallel arrays."
#
#   for (( i=0; ... )) -- C-style for loop.  Bash supports a counting loop
#                      syntax borrowed from C:
#                        for (( i=0; i<n; i++ )); do ... done
#                      This is the cleanest way to iterate over parallel
#                      arrays by index.
#
#   ${#array[@]}   -- The number of elements in an indexed array.  The #
#                     prefix means "length of."  @ means "all elements."
#
#   [[ -d path ]]  -- Test whether a DIRECTORY exists.  Returns true (0) if
#                     the path is an existing directory, false (1) otherwise.
#                     Compare with -f (test for regular file).
#
#   ${VAR:-default} -- Parameter expansion with default.  If VAR is unset or
#                      empty, use "default" instead.  We use this to fall back
#                      to $USER when SUDO_USER is not set (i.e. the script
#                      was run without sudo).
# ===========================================================================

# ---- Strict mode -----------------------------------------------------------
# -e  : Exit immediately if any command returns non-zero.
# -u  : Treat references to unset variables as errors.
# -o pipefail : A pipeline fails if ANY stage fails (not just the last).
set -euo pipefail

# ---- Source the shared library ---------------------------------------------
# "$(dirname "$0")" resolves to the directory containing THIS script (scripts/).
# Sourcing lib.sh gives us: log_info, log_ok, log_fail, log_skip, run_cmd,
# print_header, print_summary, setup_logging, REPO_DIR, etc.
source "$(dirname "$0")/lib.sh"

# ---- Initialise logging ---------------------------------------------------
# Creates a timestamped log file under logs/ and resets the SECONDS timer
# that print_summary uses to report total duration.
setup_logging

# ---- Section name ----------------------------------------------------------
# A short label that groups every log line from this script together in the
# summary table.  We set it to PASS initially; run_cmd will flip it to FAIL
# if any command fails.
SECTION="GIT-TOOLS"
SECTION_RESULTS["$SECTION"]="PASS"

# ---- Print a header -------------------------------------------------------
print_header "Git-Clone Tools"

# ===========================================================================
# Determine the real (non-root) user
# ===========================================================================
# When this script is invoked with sudo, the effective user ($USER) is "root",
# but SUDO_USER holds the name of the person who actually ran the sudo command.
# We need this because:
#   1. We want to clone repos into that user's ~/tools/, not /root/tools/.
#   2. We want the cloned files to be OWNED by that user, not by root.
#
# ${SUDO_USER:-$USER} means: use SUDO_USER if it is set and non-empty;
# otherwise fall back to $USER.  This makes the script work both with and
# without sudo.
REAL_USER="${SUDO_USER:-$USER}"

# Look up the real user's home directory from /etc/passwd.  We cannot just use
# $HOME because when running under sudo, $HOME is sometimes (depending on
# sudo configuration) set to /root.  The tilde (~) expansion also uses the
# effective user, so ~/ would expand to /root/.  Reading from the password
# database via getent is the most reliable method.
#
# getent passwd USERNAME  -- queries the system user database (like /etc/passwd)
#                            and returns a colon-delimited record:
#                            username:x:uid:gid:gecos:homedir:shell
#
# cut -d: -f6             -- splits on ':' and picks the 6th field (homedir).
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# TOOLS_DIR is where all standalone git tools will be cloned.
TOOLS_DIR="${REAL_HOME}/tools"

# ===========================================================================
# STEP 1: Create the ~/tools/ directory
# ===========================================================================
# -p means "no error if it already exists, and create parent directories as
# needed."  We do this as the real user so the directory is not owned by root.
log_info "$SECTION" "Ensuring ${TOOLS_DIR} exists..."

if [[ -d "$TOOLS_DIR" ]]; then
    log_skip "$SECTION" "Create ${TOOLS_DIR}" "already exists"
else
    run_cmd "$SECTION" "Create ${TOOLS_DIR}" \
        sudo -u "$REAL_USER" mkdir -p "$TOOLS_DIR"
fi

# ===========================================================================
# STEP 2: Define the list of tools to clone
# ===========================================================================
# We use PARALLEL ARRAYS to store the tool name and its git URL side-by-side.
# Bash indexed arrays (declared with =( ... )) are zero-based.  We use the
# same numeric index to access TOOL_NAMES[i] and TOOL_URLS[i], which keeps
# each tool's name paired with its URL.
#
# Why not an associative array?  Associative arrays (declare -A) would work
# for name->URL mapping, but they do NOT preserve insertion order.  When you
# iterate over "${!assoc[@]}" the keys come out in hash order, which is
# unpredictable.  Parallel indexed arrays keep the tools in the exact order
# we define them, which makes the output deterministic and easier to read.

TOOL_NAMES=(
    "CVE-2020-1472"   # ZeroLogon -- Netlogon privilege escalation exploit (PoC)
    "bloodyAD"        # Active Directory privilege escalation & persistence via LDAP
    "beanshooter"     # Java Management Extensions (JMX) exploitation tool
    "noPac"           # CVE-2021-42278/CVE-2021-42287 -- AD privilege escalation
    "hawktrace"       # Internal / custom BLS reconnaissance tool
)

TOOL_URLS=(
    "https://github.com/dirkjanm/CVE-2020-1472"
    "https://github.com/CravateRouge/bloodyAD"
    "https://github.com/qtc-de/beanshooter"
    "https://github.com/Ridter/noPac"
    "https://github.com/blacklanternsecurity/hawktrace"
)

# ===========================================================================
# STEP 3: Clone each tool
# ===========================================================================
# Counters so we can log a summary line at the end, like the other scripts.
success_count=0
fail_count=0
skip_count=0

# ${#TOOL_NAMES[@]} expands to the number of elements in the TOOL_NAMES array.
# We store it in a variable for clarity (and so the for-loop header is shorter).
tool_count=${#TOOL_NAMES[@]}

log_info "$SECTION" "Cloning ${tool_count} tools into ${TOOLS_DIR}..."

# ---- C-style for loop over parallel arrays ---------------------------------
# for (( i=0; i<tool_count; i++ ))
#   - (( )) is the arithmetic evaluation context.
#   - i=0        : initialise counter to 0 (arrays are zero-indexed).
#   - i<tool_count : loop while i is less than the number of tools.
#   - i++        : increment i after each iteration.
#
# Inside the loop, TOOL_NAMES[$i] and TOOL_URLS[$i] give us the name and URL
# for the same tool.
for (( i=0; i<tool_count; i++ )); do

    name="${TOOL_NAMES[$i]}"
    url="${TOOL_URLS[$i]}"

    # The clone destination: ~/tools/<tool_name>
    tool_dir="${TOOLS_DIR}/${name}"

    # ---- Idempotency check -------------------------------------------------
    # [[ -d "$tool_dir" ]] tests whether the directory already exists.
    # If it does, we skip the clone to avoid errors ("destination path already
    # exists") and wasted bandwidth.  This makes the script safe to re-run.
    if [[ -d "$tool_dir" ]]; then
        log_skip "$SECTION" "Clone ${name}" "already exists"
        skip_count=$((skip_count + 1))
    else
        # ---- Clone as the real user ----------------------------------------
        # `sudo -u "$REAL_USER"` runs the git-clone as the non-root user.
        # This ensures the cloned files are owned by brad (or whoever ran
        # sudo), not by root.  Without this, the user would need to chown
        # the entire ~/tools/ tree after every run.
        #
        # git clone <url> <destination>
        #   --depth 1 could be added here to save bandwidth (shallow clone),
        #   but we do a full clone so the user can browse the commit history
        #   for educational purposes.
        if run_cmd "$SECTION" "Clone ${name}" \
            sudo -u "$REAL_USER" git clone "$url" "$tool_dir"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    fi

done

# ===========================================================================
# Summary
# ===========================================================================
log_info "$SECTION" "----------------------------------------------"
log_info "$SECTION" "Git-clone complete: ${success_count} cloned, ${fail_count} failed, ${skip_count} skipped"
log_info "$SECTION" "----------------------------------------------"

# print_summary generates the full status table with per-section pass/fail,
# duration, failure list, and log file path.
print_summary
