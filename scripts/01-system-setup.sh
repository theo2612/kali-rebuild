#!/usr/bin/env bash
# ===========================================================================
# 01-system-setup.sh -- Add third-party apt repos, keys, and base packages
# ===========================================================================
#
# This is the FIRST install script to run.  It prepares the system so that
# every later script can assume:
#   - Third-party apt repositories (Neo4j, Signal, Sublime Text) are available
#   - Core tools (git, curl, wget, docker, go, pipx, etc.) are installed
#
# Run with:  sudo ./scripts/01-system-setup.sh
#
# ---------------------------------------------------------------------------

# ---- Strict mode -----------------------------------------------------------
# set -e   : Exit immediately if ANY command returns a non-zero exit code.
#            This stops the script at the first failure instead of silently
#            continuing, which could leave the system in a broken state.
# set -u   : Treat references to UNSET variables as an error.  Without this,
#            a typo like "$NAEM" silently expands to an empty string.
# set -o pipefail : In a pipeline (cmd1 | cmd2), bash normally only reports
#            the exit code of the LAST command.  With pipefail, the pipeline
#            fails if ANY command in it fails.  This is critical because we
#            pipe wget output into gpg -- we want to know if wget fails.
set -euo pipefail

# ---- Load the shared library -----------------------------------------------
# "source" (also written as ".") reads another file and executes it inside
# THIS shell.  After sourcing lib.sh we can call its functions -- log_info,
# run_cmd, print_header, print_summary, etc. -- as if they were defined here.
#
# $(dirname "$0") expands to the directory containing THIS script (scripts/).
# So this always finds lib.sh no matter where you call the script from.
source "$(dirname "$0")/lib.sh"

# ---- Initialise logging ----------------------------------------------------
# setup_logging creates a timestamped log file under logs/ and resets the
# timer that print_summary uses to show total duration.
setup_logging

# ---- Section name -----------------------------------------------------------
# We use a short constant for the section tag so every log line in this script
# is grouped together in the summary table.
SECTION="SYS-SETUP"

# Initialise this section in the results tracker.  SECTION_RESULTS is an
# associative array defined in lib.sh.  Setting it to "PASS" here means it
# will show as PASS in the summary unless a run_cmd call flips it to FAIL.
SECTION_RESULTS["$SECTION"]="PASS"

# ---- Print a header --------------------------------------------------------
# print_header outputs a prominent banner so the user knows which phase of the
# install is running.  It auto-numbers steps.
print_header "System Setup"

# ===========================================================================
# STEP 1: Add third-party APT repositories
# ===========================================================================
#
# Why signing keys?
# -----------------
# When you add a third-party repository, apt needs a way to verify that the
# packages it downloads actually came from that project and have not been
# tampered with.  Each repository publishes a GPG public key.  We download
# that key and store it locally.  apt then checks every package against the
# key -- if the signature does not match, the install is refused.
#
# The workflow for each repo is:
#   1. Download the project's GPG public key and convert ("dearmor") it from
#      ASCII-armored format to the binary format apt expects.
#   2. Copy the .list or .sources file (which tells apt the repository URL
#      and which signing key to use) into /etc/apt/sources.list.d/.
#
# REPO_DIR is set by lib.sh and points to the root of this git repository
# (e.g. /home/brad/kali-rebuild).  We use it to locate our config files.
# ===========================================================================

# ---- Neo4j repository ------------------------------------------------------
# Neo4j is a graph database used by BloodHound for Active Directory analysis.
log_info "$SECTION" "Adding Neo4j repository..."

run_cmd "$SECTION" "Download Neo4j signing key" \
    bash -c 'wget -qO- https://debian.neo4j.com/neotechnology.gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/neo4j.gpg'

run_cmd "$SECTION" "Copy Neo4j sources list" \
    cp "${REPO_DIR}/configs/apt/sources.list.d/neo4j.list" /etc/apt/sources.list.d/

# ---- Signal Desktop repository ---------------------------------------------
# Signal is a privacy-focused messenger.
log_info "$SECTION" "Adding Signal Desktop repository..."

run_cmd "$SECTION" "Download Signal signing key" \
    bash -c 'wget -qO- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor --yes -o /usr/share/keyrings/signal-desktop-keyring.gpg'

run_cmd "$SECTION" "Copy Signal sources file" \
    cp "${REPO_DIR}/configs/apt/sources.list.d/signal-desktop.sources" /etc/apt/sources.list.d/

# ---- Sublime Text repository -----------------------------------------------
# Sublime Text is a fast, lightweight code editor.
log_info "$SECTION" "Adding Sublime Text repository..."

run_cmd "$SECTION" "Download Sublime Text signing key" \
    bash -c 'wget -qO- https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/sublimehq.gpg'

run_cmd "$SECTION" "Copy Sublime Text sources list" \
    cp "${REPO_DIR}/configs/apt/sources.list.d/sublime-text.list" /etc/apt/sources.list.d/

# ===========================================================================
# STEP 2: Update the package cache
# ===========================================================================
# After adding new repos we must run "apt-get update" so apt fetches the
# package lists from those repositories.  Without this, apt would not know
# about any packages in the newly added repos.
log_info "$SECTION" "Updating apt package cache..."

run_cmd "$SECTION" "apt-get update" \
    apt-get update -qq

# ===========================================================================
# STEP 3: Install base dependencies
# ===========================================================================
# These packages are needed by scripts that run later:
#
#   git            -- Clone GitHub repositories
#   curl           -- Download files (some tools prefer curl over wget)
#   wget           -- Download files (used above for signing keys)
#   gpg            -- GNU Privacy Guard, needed to verify signing keys
#   pipx           -- Install Python CLI tools in isolated environments
#   docker.io      -- Container runtime for tools distributed as Docker images
#   docker-compose -- Define and run multi-container Docker applications
#   golang         -- Go compiler, needed to build Go-based security tools
#
# -y answers "yes" to the install confirmation prompt so the script runs
# unattended.  -qq makes apt quieter (less progress noise).
log_info "$SECTION" "Installing base dependencies..."

run_cmd "$SECTION" "Install base packages" \
    apt-get install -y -qq \
        git \
        curl \
        wget \
        gpg \
        pipx \
        docker.io \
        docker-compose \
        golang

# ===========================================================================
# STEP 4: Ensure pipx PATH is configured
# ===========================================================================
# pipx installs Python tools into ~/.local/bin.  "pipx ensurepath" adds that
# directory to $PATH in the user's shell config so the tools can be found.
# This is safe to run multiple times -- it only adds the entry if missing.
#
# IMPORTANT: We run this as the REAL user (not root) because pipx ensurepath
# modifies the user's shell config (~/.bashrc, ~/.zshrc).  If we ran it as
# root, it would modify /root/.bashrc instead of /home/brad/.bashrc.
REAL_USER="${SUDO_USER:-$USER}"
log_info "$SECTION" "Configuring pipx PATH for ${REAL_USER}..."

run_cmd "$SECTION" "pipx ensurepath" \
    sudo -u "$REAL_USER" pipx ensurepath

# ---- Summary ---------------------------------------------------------------
# print_summary reads the SECTION_RESULTS table and FAILURES list that run_cmd
# has been updating, then prints a nice pass/fail summary with timing info.
print_summary
