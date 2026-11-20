#!/usr/bin/env bash
# ===========================================================================
# 06-docker-services.sh -- Set up BloodHound CE via Docker Compose
# ===========================================================================
#
# This script automates the deployment of BloodHound Community Edition (CE),
# an Active Directory reconnaissance tool used by penetration testers to
# visualise attack paths.  BloodHound runs as a set of Docker containers
# (the app itself, a PostgreSQL database, and a Neo4j graph database)
# orchestrated by Docker Compose.
#
# The script:
#   1. Creates a ~/bloodhound/ directory for the real (non-root) user
#   2. Copies the Docker Compose file and config template into it
#   3. Generates a random admin password and injects it into the config
#   4. Enables the Docker daemon, adds the user to the docker group
#   5. Pulls the container images and starts the stack
#
# Run with:  sudo ./scripts/06-docker-services.sh
#
# ---------------------------------------------------------------------------
# BASH CONCEPTS COVERED IN THIS SCRIPT
#
# Command substitution -- $(command)
#   The shell runs 'command' in a subshell, captures its stdout, and
#   replaces $(...) with that output.  We use this to generate a random
#   password: BH_PASSWORD="$(tr ... | head -c 32)".  The inner pipeline
#   runs first, its output becomes the value of BH_PASSWORD.
#
# getent passwd for resolving a user's home directory
#   getent queries system databases (like /etc/passwd).  The output format is:
#     username:x:uid:gid:full_name:home_dir:shell
#   We pipe to "cut -d: -f6" to extract just the home directory (field 6).
#   This is safer than "eval echo ~user" because eval can execute arbitrary
#   code if the variable contains shell metacharacters.
#
# sed for text replacement
#   sed (Stream EDitor) reads input line by line and applies transformations.
#   The 's/PATTERN/REPLACEMENT/g' command substitutes every occurrence of
#   PATTERN with REPLACEMENT.  The 'g' flag means "global" -- replace all
#   matches on each line, not just the first.  We use sed to swap a
#   placeholder string in the config template with the generated password.
#
# systemctl for service management
#   systemctl is the command-line interface to systemd, which manages system
#   services (daemons) on modern Linux.  Key subcommands:
#     enable  -- start the service automatically on boot
#     start   -- start the service right now
#     --now   -- shorthand for "enable AND start in one command"
#   So `systemctl enable --now docker` both enables Docker at boot and starts
#   it immediately.
#
# usermod -aG for adding users to groups
#   usermod modifies a user account.  The flags:
#     -a  : "append" -- add the user to the group WITHOUT removing them
#           from any groups they are already in.  Without -a, the user's
#           group list would be REPLACED (very dangerous!).
#     -G  : specifies a supplementary group to add the user to.
#   So `usermod -aG docker brad` adds brad to the docker group, allowing
#   brad to run Docker commands without sudo.  The change takes effect at
#   next login (existing shells keep the old group list).
# ===========================================================================

# ---- Strict mode -----------------------------------------------------------
# set -e   : Exit immediately if any command returns a non-zero exit code.
# set -u   : Treat references to unset variables as errors.
# set -o pipefail : In a pipeline, fail if ANY command fails, not just the last.
set -euo pipefail

# ---- Load the shared library -----------------------------------------------
# "source" (also written as ".") reads lib.sh and executes it inside THIS
# shell so we get access to run_cmd, log_info, print_header, etc.
#
# $(dirname "$0") expands to the directory containing this script (scripts/),
# so lib.sh is always found regardless of the working directory.
source "$(dirname "$0")/lib.sh"

# ---- Initialise logging ----------------------------------------------------
# setup_logging creates a timestamped log file under logs/ and resets the
# SECONDS timer so print_summary can report how long the run took.
setup_logging

# ---- Section name -----------------------------------------------------------
# SECTION is the label that appears in log output and the summary table.
# We set SECTION_RESULTS to "PASS" so it starts green; run_cmd will flip
# it to "FAIL" if anything goes wrong.
SECTION="DOCKER"
SECTION_RESULTS["$SECTION"]="PASS"

# ---- Print a header --------------------------------------------------------
print_header "Docker Services"

# ===========================================================================
# STEP 1: Determine the real user's home directory
# ===========================================================================
#
# This script runs as root (via sudo), but we need to create files in the
# REAL user's home directory, not /root.  When you run `sudo ./script.sh`,
# the environment variable SUDO_USER is automatically set to the name of
# the user who invoked sudo (e.g. "brad").
#
# We use eval echo to expand the tilde (~) for that username:
#   1. "${SUDO_USER}" expands to e.g. "brad"
#   2. eval re-parses "echo ~brad", expanding ~brad to /home/brad
#
# This is more reliable than hardcoding /home/$SUDO_USER because some
# systems place home directories elsewhere (e.g. /usr/home/ on FreeBSD).
REAL_USER="${SUDO_USER:-$(whoami)}"
# Look up the user's home directory from the system password database.
# getent passwd returns a colon-delimited record; field 6 is the home directory.
# This is safer than "eval echo ~user" because it avoids eval's code execution risks.
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

log_info "$SECTION" "Real user: ${REAL_USER}, home: ${REAL_HOME}"

# ===========================================================================
# STEP 2: Create the BloodHound directory
# ===========================================================================
# We create ~/bloodhound/ to hold the Docker Compose file and the
# BloodHound configuration file.  mkdir -p creates the directory and does
# not error if it already exists.
BH_DIR="${REAL_HOME}/bloodhound"

run_cmd "$SECTION" "Create ${BH_DIR} directory" \
    mkdir -p "$BH_DIR"

# ===========================================================================
# STEP 3: Copy the Docker Compose file
# ===========================================================================
# The docker-compose.yml defines the three services (bloodhound, postgres,
# neo4j), their network connections, volumes, and health checks.  We ship
# it in the repo under configs/bloodhound/ and copy it to the user's
# ~/bloodhound/ directory where docker compose expects to find it.
run_cmd "$SECTION" "Copy docker-compose.yml to ${BH_DIR}" \
    cp "${REPO_DIR}/configs/bloodhound/docker-compose.yml" "${BH_DIR}/docker-compose.yml"

# ===========================================================================
# STEP 4/5: Create bloodhound.config.json with a random admin password
# ===========================================================================
# The template at configs/bloodhound/bloodhound.config.json contains the
# placeholder "GENERATED_AT_INSTALL_TIME" in two places:
#   - default_admin.password  (the admin user's initial password)
#   - default_password        (the default password for new users)
#
# IMPORTANT -- only do this ONCE.  BloodHound reads default_admin.password
# only when it first initialises its database.  The database lives in a
# Docker volume that survives re-runs of this script, so generating a new
# password on a re-run just prints a password that doesn't work.  If the
# config already exists we leave it alone.  (To truly start over: run
# `docker compose down -v` in ~/bloodhound, delete bloodhound.config.json,
# then re-run this script.)
#
# Password generation:
#   tr -dc 'A-Za-z0-9' </dev/urandom  -- read the kernel's CSPRNG and delete
#                                       (-d) every character NOT (-c) in the
#                                       set, leaving only letters and digits
#   head -c 32                        -- keep the first 32 of them
# 32 alphanumeric chars ~= 190 bits of entropy.  Letters and digits only
# matters: base64 output can contain "/", which breaks sed's s/// syntax,
# and "+", which is awkward to type into a login form.
#
# The password is deliberately NOT passed through run_cmd: run_cmd writes
# the full command line into the log file, which any user can read.
BH_CONFIG="${BH_DIR}/bloodhound.config.json"
BH_PASSWORD=""

if [[ -f "$BH_CONFIG" ]] && ! grep -q GENERATED_AT_INSTALL_TIME "$BH_CONFIG"; then
    log_skip "$SECTION" "Generate bloodhound.config.json" \
        "already exists -- keeping existing admin password"
else
    # `set +o pipefail` inside the $(...) subshell: head exits after 32
    # chars, so tr is killed by SIGPIPE.  That's expected, but with pipefail
    # it would make the pipeline "fail" and set -e would abort the script.
    BH_PASSWORD="$(set +o pipefail; tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
    if sed "s/GENERATED_AT_INSTALL_TIME/${BH_PASSWORD}/g" \
            "${REPO_DIR}/configs/bloodhound/bloodhound.config.json" > "$BH_CONFIG"; then
        log_ok "$SECTION" "Generate bloodhound.config.json with random password"
    else
        log_fail "$SECTION" "Generate bloodhound.config.json with random password"
    fi
fi

# ===========================================================================
# STEP 6: Fix ownership of the BloodHound directory
# ===========================================================================
# Because this script runs as root, the files we just created are owned by
# root.  We change ownership to the real user so they can manage the files
# later (edit config, view logs, etc.).
#
# chown -R USER:USER DIR  recursively changes the owner and group of all
# files and directories under DIR.
run_cmd "$SECTION" "Fix ownership of ${BH_DIR}" \
    chown -R "${REAL_USER}:${REAL_USER}" "$BH_DIR"

# ===========================================================================
# STEP 7: Enable and start the Docker service
# ===========================================================================
# systemctl enable --now docker does two things at once:
#   1. enable  -- creates a symlink so Docker starts automatically on boot
#   2. --now   -- also starts the service immediately (equivalent to
#                 running "systemctl start docker" separately)
#
# After this command, the Docker daemon is running and ready to pull images
# and start containers.
run_cmd "$SECTION" "Enable and start Docker service" \
    systemctl enable --now docker

# ===========================================================================
# STEP 8: Add the real user to the docker group
# ===========================================================================
# By default, only root can talk to the Docker daemon.  Adding the user to
# the "docker" group grants them permission to run Docker commands without
# sudo.
#
# usermod -aG docker USERNAME :
#   -a  : append (do not remove existing group memberships!)
#   -G  : specify supplementary group(s) to add
#
# IMPORTANT: Group changes only take effect at next login.  The current
# shell session still has the old group list.  We add a manual step below
# to remind the user to log out and back in.
run_cmd "$SECTION" "Add ${REAL_USER} to docker group" \
    usermod -aG docker "$REAL_USER"

# ===========================================================================
# STEP 9: Pull the BloodHound container images
# ===========================================================================
# "docker compose pull" downloads all container images referenced in the
# docker-compose.yml file.  We do this as a separate step (before "up")
# so that the download progress is logged independently from the container
# startup.
#
# The -f flag tells docker compose which compose file to use.  We point it
# at the file we just copied into ~/bloodhound/.
log_info "$SECTION" "Pulling BloodHound Docker images (this may take a few minutes)..."

run_cmd "$SECTION" "Pull BloodHound Docker images" \
    docker compose -f "${BH_DIR}/docker-compose.yml" pull

# ===========================================================================
# STEP 10: Start the BloodHound stack
# ===========================================================================
# "docker compose up -d" starts all containers defined in the compose file.
#   -d  : "detached" mode -- run containers in the background so the script
#         can continue (without -d, docker compose would block and print
#         container logs to the terminal until you press Ctrl+C).
#
# --project-directory tells Docker Compose to treat BH_DIR as the working
# directory, which is important because the compose file references
# ./bloodhound.config.json as a volume mount (relative to the project dir).
run_cmd "$SECTION" "Start BloodHound containers" \
    docker compose -f "${BH_DIR}/docker-compose.yml" --project-directory "$BH_DIR" up -d

# ===========================================================================
# STEP 11: Display the admin password
# ===========================================================================
# Printed to the terminal only (plain echo), never to the log file.  It's
# also stored in ~/bloodhound/bloodhound.config.json (default_admin.password)
# if you need it later.
if [[ -n "$BH_PASSWORD" ]]; then
    echo ""
    echo "  ${BOLD}============================================${RESET}"
    echo "  ${BOLD}BloodHound admin password: ${BH_PASSWORD}${RESET}"
    echo "  Also stored in ${BH_CONFIG} (default_admin.password)"
    echo "  ${BOLD}============================================${RESET}"
    echo ""
    log_info "$SECTION" "BloodHound admin password generated (shown on screen, stored in ${BH_CONFIG})"
else
    log_info "$SECTION" "BloodHound admin password unchanged -- see default_admin.password in ${BH_CONFIG}"
fi

# ===========================================================================
# STEP 12: Add manual steps
# ===========================================================================
# add_manual_step records a reminder that will be displayed in the summary.
# These are things the script cannot do automatically -- the user must
# perform them by hand after the script finishes.

# Group membership changes require a new login session to take effect.
# Running "id" in the current shell will NOT show the docker group yet.
add_manual_step "Log out and back in for docker group membership to take effect"

# The BloodHound web UI is now running but the user needs to know where
# to find it and what credentials to use.
add_manual_step "Log in to BloodHound at http://127.0.0.1:8080 (user: admin)"

# ---- Summary ---------------------------------------------------------------
# print_summary outputs the pass/fail table, failure list, manual steps,
# total duration, and the log file path.
print_summary
