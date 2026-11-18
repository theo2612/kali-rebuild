#!/usr/bin/env bash
# ===========================================================================
# 07-configs.sh -- Install dotfiles and shell configurations
# ===========================================================================
#
# This script copies dotfiles (shell configs, gitconfig) from the repo's
# configs/ directory into the real user's home directory.  It backs up any
# existing files before overwriting so nothing is lost.
#
# WHY A SEPARATE SCRIPT FOR CONFIGS?
# -----------------------------------
# Dotfiles control your shell prompt, aliases, PATH, git identity, and many
# other personalisation settings.  Keeping them in version control (inside
# this repo) means you can rebuild your environment on a fresh machine in
# seconds and track every change over time with git.
#
# This script handles:
#   1. Backing up existing dotfiles (*.bak) so you can restore them later
#   2. Copying the repo's configs into ~/ with a leading "." (dot prefix)
#   3. Fixing file ownership so the files belong to the real user, not root
#
# USAGE (run as root or with sudo):
#   sudo ./scripts/07-configs.sh
#
# ---------------------------------------------------------------------------
# BASH CONCEPTS USED IN THIS SCRIPT
#
# Arrays for iteration  -- SHELL_CONFIGS=("zshrc" "bashrc" ...) creates an
#                          indexed array.  We loop over it with a for loop
#                          to avoid repeating the same backup-copy-chown
#                          logic for each file.
#
# String operations     -- ".${config}" prepends a literal dot to the
#                          filename.  configs/zshrc becomes ~/.zshrc.  This
#                          is simple string concatenation in bash: just put
#                          the pieces next to each other.
#
# Conditional backup    -- if [[ -f "$target" ]]; then cp ...; fi
#                          The -f test returns true if the path exists AND
#                          is a regular file (not a directory, not a symlink
#                          to a directory).  We only back up when there is
#                          something to back up.
#
# ${VAR:-default}       -- Parameter expansion with a default value.
#                          ${SUDO_USER:-$(whoami)} means: "use $SUDO_USER
#                          if it is set and non-empty; otherwise, fall back
#                          to the output of whoami."  This is essential
#                          because when you run `sudo ./script.sh`, $USER
#                          becomes "root", but $SUDO_USER remembers who
#                          actually typed the command (e.g. "brad").
#
# eval echo "~user"     -- Tilde (~) expansion does NOT happen inside
#                          double quotes or variables.  If REAL_USER=brad,
#                          then echo "~${REAL_USER}" literally prints
#                          ~brad, not /home/brad.  Using eval forces the
#                          shell to re-evaluate the string, which triggers
#                          tilde expansion and gives us /home/brad.
#
# chown USER:USER file  -- Changes the owner AND group of a file.  When a
#                          script runs as root (via sudo), any files it
#                          creates or copies are owned by root.  We use
#                          chown to hand ownership back to the real user
#                          so they can edit their own dotfiles later.
# ===========================================================================

# ---- Strict mode -----------------------------------------------------------
# set -e   : Exit immediately if ANY command returns a non-zero exit code.
# set -u   : Treat references to UNSET variables as an error.
# set -o pipefail : In a pipeline, fail if ANY command fails (not just last).
set -euo pipefail

# ---- Source the shared library ---------------------------------------------
# "source" reads lib.sh and executes it inside THIS shell, giving us access
# to log_info, log_ok, log_skip, log_fail, run_cmd, print_header, etc.
# $(dirname "$0") resolves to the directory containing this script (scripts/).
source "$(dirname "$0")/lib.sh"

# ---- Initialise logging ---------------------------------------------------
# Creates a timestamped log file and starts the duration timer.
setup_logging

# ---- Section name ----------------------------------------------------------
# Every log line and the final summary table will use this label.
SECTION="CONFIGS"

# Initialise this section as PASS.  If any run_cmd call fails, lib.sh
# automatically flips it to FAIL.
SECTION_RESULTS["$SECTION"]="PASS"

# ---- Print the section header ----------------------------------------------
print_header "Configs & Dotfiles"

# ===========================================================================
# STEP 1: Determine the real user's home directory
# ===========================================================================
#
# When a script runs under sudo, several environment variables change:
#   $USER     -> "root"          (the effective user)
#   $HOME     -> "/root"         (root's home directory)
#   $SUDO_USER -> "brad"         (the user who invoked sudo)
#
# We need the ORIGINAL user's home directory (e.g. /home/brad) because that
# is where dotfiles should be installed -- not in /root.
#
# ${SUDO_USER:-$(whoami)} is a parameter expansion with a default:
#   - If SUDO_USER is set and non-empty (running under sudo), use it.
#   - Otherwise, fall back to $(whoami), which returns the current username.
#     This handles the case where the script is run directly without sudo,
#     for example during testing.
REAL_USER="${SUDO_USER:-$(whoami)}"

# Look up the user's home directory from the system password database.
# getent passwd returns a colon-delimited record like:
#   brad:x:1000:1000:Brad Theodore:/home/brad:/usr/bin/zsh
# We use cut -d: -f6 to extract the 6th field (the home directory).
#
# This is safer and more reliable than "eval echo ~${REAL_USER}" because:
#   - eval can execute arbitrary code if the variable contains shell metacharacters
#   - getent reads directly from the system database (works even on unusual setups)
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

log_info "$SECTION" "Real user: ${REAL_USER}"
log_info "$SECTION" "Home directory: ${REAL_HOME}"

# ===========================================================================
# STEP 2: Install shell configuration files
# ===========================================================================
#
# We keep the repo filenames WITHOUT the leading dot (e.g. configs/zshrc)
# because dotfiles (files starting with .) are hidden by default in ls and
# file managers.  Keeping them visible in the repo makes them easier to find
# and edit.  This script adds the dot when copying them into ~/.
#
# SHELL_CONFIGS is an indexed array.  Arrays in bash:
#   - Are declared with parentheses: VAR=("a" "b" "c")
#   - Elements are accessed with ${VAR[0]}, ${VAR[1]}, etc.
#   - "${VAR[@]}" expands to ALL elements, each as a separate word
#   - ${#VAR[@]} gives the count of elements
#
# We use an array so we can loop over multiple files with one block of logic
# instead of copying and pasting the backup-copy-chown steps for each file.
SHELL_CONFIGS=("zshrc" "bashrc" "profile" "zprofile")

log_info "$SECTION" "Installing ${#SHELL_CONFIGS[@]} shell config files..."

# ---- Loop over each shell config file --------------------------------------
# "for config in "${SHELL_CONFIGS[@]}"" iterates over every element in the
# array.  On each iteration, $config takes on the next value:
#   Iteration 1: config=zshrc
#   Iteration 2: config=bashrc
#   Iteration 3: config=profile
#   Iteration 4: config=zprofile
for config in "${SHELL_CONFIGS[@]}"; do

    # Build the source and target paths.
    # source_file: the config in the repo (e.g. /home/brad/kali-rebuild/configs/zshrc)
    # target_file: where it goes in the home dir (e.g. /home/brad/.zshrc)
    #
    # ".${config}" prepends a dot to the filename.  This is simple string
    # concatenation -- bash just glues the pieces together:
    #   "." + "zshrc" = ".zshrc"
    source_file="${REPO_DIR}/configs/${config}"
    target_file="${REAL_HOME}/.${config}"

    # ---- Verify the source file exists in the repo -------------------------
    # If someone deleted a config from configs/, we skip it rather than crash.
    if [[ ! -f "$source_file" ]]; then
        log_skip "$SECTION" "Install .${config}" "source not found: ${source_file}"
        continue
    fi

    # ---- Back up the existing file if it exists ----------------------------
    # [[ -f "$target_file" ]] tests if the target is a regular file that
    # already exists.  If it does, we make a backup copy with a .bak suffix
    # BEFORE overwriting it.  This way the user can always restore their
    # previous config with: cp ~/.zshrc.bak ~/.zshrc
    #
    # We use run_cmd for the backup so it gets logged and any failure is
    # captured in the summary.
    if [[ -f "$target_file" ]]; then
        run_cmd "$SECTION" "Backup .${config}" \
            cp "$target_file" "${target_file}.bak"
    else
        log_info "$SECTION" "No existing .${config} to back up"
    fi

    # ---- Copy the config from the repo to the home directory ---------------
    run_cmd "$SECTION" "Install .${config}" \
        cp "$source_file" "$target_file"

done

# ===========================================================================
# STEP 3: Install gitconfig
# ===========================================================================
#
# Git reads its user-level configuration from ~/.gitconfig.  This file
# typically contains your name, email, preferred editor, aliases, and other
# settings.  We handle it separately from the shell configs above just for
# clarity, but the backup-copy pattern is identical.
log_info "$SECTION" "Installing gitconfig..."

GITCONFIG_SRC="${REPO_DIR}/configs/gitconfig"
GITCONFIG_DST="${REAL_HOME}/.gitconfig"

if [[ ! -f "$GITCONFIG_SRC" ]]; then
    log_skip "$SECTION" "Install .gitconfig" "source not found: ${GITCONFIG_SRC}"
else
    # ---- Back up existing .gitconfig if present ----------------------------
    if [[ -f "$GITCONFIG_DST" ]]; then
        run_cmd "$SECTION" "Backup .gitconfig" \
            cp "$GITCONFIG_DST" "${GITCONFIG_DST}.bak"
    else
        log_info "$SECTION" "No existing .gitconfig to back up"
    fi

    # ---- Copy the gitconfig into place ------------------------------------
    run_cmd "$SECTION" "Install .gitconfig" \
        cp "$GITCONFIG_SRC" "$GITCONFIG_DST"
fi

# ===========================================================================
# STEP 4: Install XFCE display settings
# ===========================================================================
#
# On a fresh Kali install, XFCE defaults to the panel's native resolution
# with no scaling.  On a HiDPI laptop (2880x1920), this makes everything
# tiny.  These config files restore our preferred scaling, resolution, and
# font settings.
#
# The target directory is ~/.config/xfce4/xfconf/xfce-perchannel-xml/
# which is where XFCE stores per-channel settings as XML files.  Unlike
# shell dotfiles (which go directly in ~/), these live in a nested
# directory structure, so we need to create the directory first.
#
# mkdir -p creates the directory AND any missing parent directories.
# The -p flag means "no error if existing, make parent directories as
# needed."  Without -p, mkdir fails if the parent does not exist.

XFCE_CONF_DIR="${REAL_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"

log_info "$SECTION" "Installing XFCE display settings..."

# Create the target directory if it does not exist yet.
# On a fresh install, ~/.config/xfce4/ may not exist until the user
# logs into XFCE for the first time.  We create it ahead of time so
# XFCE picks up our settings on first login.
run_cmd "$SECTION" "Create XFCE config directory" \
    mkdir -p "$XFCE_CONF_DIR"

# XFCE_CONFIGS is an array of the config files we want to deploy.
# Each entry is the filename as it appears in both the repo (configs/xfce4/)
# and the target directory.  Unlike shell dotfiles, these do NOT get a
# leading dot -- XFCE expects the plain filename.
XFCE_CONFIGS=("displays.xml" "xsettings.xml")

for config in "${XFCE_CONFIGS[@]}"; do
    source_file="${REPO_DIR}/configs/xfce4/${config}"
    target_file="${XFCE_CONF_DIR}/${config}"

    if [[ ! -f "$source_file" ]]; then
        log_skip "$SECTION" "Install ${config}" "source not found: ${source_file}"
        continue
    fi

    if [[ -f "$target_file" ]]; then
        run_cmd "$SECTION" "Backup ${config}" \
            cp "$target_file" "${target_file}.bak"
    else
        log_info "$SECTION" "No existing ${config} to back up"
    fi

    run_cmd "$SECTION" "Install ${config}" \
        cp "$source_file" "$target_file"
done

# ===========================================================================
# STEP 5: Fix file ownership
# ===========================================================================
#
# When this script runs under sudo, every file it creates or copies is owned
# by root (uid 0).  That is a problem because:
#   - The user cannot edit their own dotfiles without sudo
#   - Some programs (like ssh) refuse to use config files owned by another user
#   - It is confusing and breaks the principle of least privilege
#
# chown USER:GROUP FILE changes the file's owner and group.  Using
# ${REAL_USER}:${REAL_USER} sets BOTH the owner and the primary group to
# the real user.  On most Linux systems, each user has a matching group
# with the same name (e.g. user "brad", group "brad").
#
# We build an array of ALL the files we installed (including .bak backups
# if they exist), then chown them in one pass.  This is more efficient than
# running chown separately for each file.
log_info "$SECTION" "Fixing file ownership for ${REAL_USER}..."

# ---- Build the list of ALL config files we may have installed --------------
# ALL_CONFIGS combines the shell configs with gitconfig into one array.
# We add "gitconfig" to the SHELL_CONFIGS list for the ownership fix.
ALL_CONFIGS=("${SHELL_CONFIGS[@]}" "gitconfig")

# ---- Loop over each config and chown the file (and its backup) -------------
for config in "${ALL_CONFIGS[@]}"; do
    target_file="${REAL_HOME}/.${config}"

    # Only chown files that actually exist.  If the source was missing and
    # we skipped the install above, there is nothing to chown.
    if [[ -f "$target_file" ]]; then
        run_cmd "$SECTION" "chown .${config}" \
            chown "${REAL_USER}:${REAL_USER}" "$target_file"
    fi

    # Also fix ownership on the backup file if one was created.
    if [[ -f "${target_file}.bak" ]]; then
        run_cmd "$SECTION" "chown .${config}.bak" \
            chown "${REAL_USER}:${REAL_USER}" "${target_file}.bak"
    fi
done

# ---- Fix ownership on the XFCE config directory and its contents ----------
# chown -R applies the ownership change RECURSIVELY -- meaning it changes
# the directory itself AND every file and subdirectory inside it.  This is
# needed because we used mkdir -p above (which created directories as root)
# and copied files into them (also as root).
if [[ -d "${REAL_HOME}/.config/xfce4" ]]; then
    run_cmd "$SECTION" "chown XFCE config directory" \
        chown -R "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.config/xfce4"
fi

# ===========================================================================
# Summary
# ===========================================================================
# Log a final status line, then call print_summary to output the full
# pass/fail table, duration, and log file path.
log_info "$SECTION" "----------------------------------------------"
log_info "$SECTION" "Configs & dotfiles installation complete"
log_info "$SECTION" "----------------------------------------------"

print_summary
