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
#   password: BH_PASSWORD=$(openssl rand -base64 24).  The inner command
#   (openssl rand) runs first, its output becomes the value of BH_PASSWORD.
#
# eval echo ~username -- expanding another user's home directory
#   The tilde (~) only expands to a home directory when it appears literally
#   at the start of a word.  When the username is in a variable, ~ does not
#   expand automatically.  We use eval to force a second round of parsing:
#     eval echo "~${SUDO_USER}"
#   First, bash substitutes $SUDO_USER (e.g. "brad"), producing:
#     eval echo ~brad
#   Then eval re-parses that string, and now ~brad is a literal tilde-
#   username at the start of a word, so bash expands it to /home/brad.
#   CAUTION: eval can be dangerous with untrusted input because it executes
#   arbitrary code.  Here SUDO_USER is set by sudo itself, so it is safe.
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
REAL_HOME=$(eval echo "~${REAL_USER}")

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
# STEP 4: Generate a random BloodHound admin password
# ===========================================================================
# openssl rand -base64 24  generates 24 random bytes and encodes them in
# base64, producing a 32-character string.  Command substitution $(...) runs
# the command and captures its stdout into BH_PASSWORD.
#
# Why openssl rand?
#   - It uses a cryptographically secure random number generator (CSPRNG)
#   - base64 encoding ensures the output contains only printable ASCII
#     characters (A-Z, a-z, 0-9, +, /), which is safe for JSON strings
#   - 24 bytes of entropy = 192 bits, which is far more than enough for a
#     password (128 bits is considered uncrackable by brute force)
BH_PASSWORD=$(openssl rand -base64 24)

log_info "$SECTION" "Generated random admin password for BloodHound"

# ===========================================================================
# STEP 5: Create bloodhound.config.json from template
# ===========================================================================
# The template at configs/bloodhound/bloodhound.config.json contains the
# placeholder string "GENERATED_AT_INSTALL_TIME" in two places:
#   - default_admin.password  (the admin user's initial password)
#   - default_password        (the default password for new users)
#
# We use sed to replace that placeholder with the generated password.
#
# sed 's/OLD/NEW/g' :
#   s       -- the substitute command
#   /OLD/   -- the pattern to find (our placeholder string)
#   /NEW/   -- the replacement text (the generated password)
#   g       -- global flag: replace ALL occurrences, not just the first
#
# The input is read from the template file and the output is redirected (>)
# to the destination file.  This is a common pattern: read a template,
# transform it, write the result somewhere else.
#
# We use bash -c because run_cmd passes each argument as a separate word to
# the command, but here we need shell features (the pipe and redirection)
# that only work inside a shell.
run_cmd "$SECTION" "Generate bloodhound.config.json with random password" \
    bash -c "sed 's/GENERATED_AT_INSTALL_TIME/${BH_PASSWORD}/g' \
        '${REPO_DIR}/configs/bloodhound/bloodhound.config.json' \
        > '${BH_DIR}/bloodhound.config.json'"

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
# STEP 11: Display the generated admin password
# ===========================================================================
# This is critical -- the password was randomly generated and exists only in
# this script's memory and in bloodhound.config.json.  If the user does not
# save it now, they will need to look inside the config file to find it.
log_info "$SECTION" "============================================"
log_info "$SECTION" "BloodHound admin password: ${BH_PASSWORD}"
log_info "$SECTION" "Save this password! It won't be shown again."
log_info "$SECTION" "============================================"

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
