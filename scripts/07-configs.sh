#!/usr/bin/env bash
# ===========================================================================
# 07-configs.sh -- Install dotfiles and desktop settings
# ===========================================================================
#
# This script sets up the real user's personal configuration:
#   1. Dotfiles (.zshrc, .tmux.conf, .gitconfig, tmux-logging scripts, ...)
#      from the separate dotfiles repo, installed as a BARE git repo
#   2. XFCE display + font settings from this repo's configs/xfce4/
#
# WHY ARE DOTFILES IN A SEPARATE REPO?
# ------------------------------------
# The same dotfiles are used on Kali (this repo) and on an Ubuntu ops box.
# Keeping them in their own repo means one source of truth for both.  This
# repo only holds Kali-specific things (tools, apt packages, XFCE settings).
#
# USAGE (run as root or with sudo):
#   sudo ./scripts/07-configs.sh
#
# ---------------------------------------------------------------------------
# BASH / GIT CONCEPTS USED IN THIS SCRIPT
#
# Bare repository       -- `git clone --bare` downloads ONLY the .git data
#                          (history, branches) with no files checked out.
#                          We store it in ~/.dotfiles and tell git that the
#                          "work tree" (where files live) is $HOME itself:
#                            git --git-dir=~/.dotfiles --work-tree=~ ...
#                          The `dotfiles` alias in .zshrc is exactly this.
#                          Files in ~ ARE the repo -- edit them in place,
#                          then `dotfiles add/commit/push`.
#
# sudo -u USER -H CMD   -- Runs CMD as USER instead of root (-H sets $HOME
#                          to that user's home).  Everything git creates is
#                          then owned by the real user, so no chown needed.
#
# Process substitution  -- `while read ...; done < <(command)` feeds the
#                          OUTPUT of a command into a loop line by line.
#                          <(command) acts like a temporary file containing
#                          the command's output.
#
# Shell functions as    -- run_cmd runs "$@", so it can run our own helper
# commands                 functions (as_user, dotgit) just like programs.
#
# ${VAR:-default}       -- ${SUDO_USER:-$(whoami)} means: "use $SUDO_USER
#                          if set and non-empty; otherwise use whoami."
#                          Under sudo, $USER is root but $SUDO_USER is you.
# ===========================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"
setup_logging

SECTION="CONFIGS"
SECTION_RESULTS["$SECTION"]="PASS"

print_header "Configs & Dotfiles"

# ===========================================================================
# STEP 1: Determine the real user's home directory
# ===========================================================================
# Under sudo: $USER -> root, $HOME -> /root, $SUDO_USER -> the real user.
# getent passwd reads the system user database; field 6 is the home dir.
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

log_info "$SECTION" "Real user: ${REAL_USER}"
log_info "$SECTION" "Home directory: ${REAL_HOME}"

# ===========================================================================
# STEP 2: Install dotfiles (bare git repo)
# ===========================================================================
#
# The dotfiles repo is public, so it clones over HTTPS with no login --
# important on a fresh install where no SSH key exists yet.  After you add
# an SSH key to GitHub, switch the remote to SSH so you can push (see the
# manual steps printed by 08-post-install.sh).
#
# A fresh Kali home already has stock files like ~/.zshrc.  git refuses to
# overwrite files it doesn't know about, so before checkout we MOVE any
# file that the repo also tracks into ~/.pre-dotfiles-backup/.  Nothing is
# deleted.
DOTFILES_URL="https://github.com/theo2612/dotfiles.git"
DOTFILES_DIR="${REAL_HOME}/.dotfiles"
BACKUP_DIR="${REAL_HOME}/.pre-dotfiles-backup"

as_user() { sudo -u "$REAL_USER" -H "$@"; }
dotgit()  { as_user git --git-dir="$DOTFILES_DIR" --work-tree="$REAL_HOME" "$@"; }

log_info "$SECTION" "Installing dotfiles from ${DOTFILES_URL}..."

if [[ -d "$DOTFILES_DIR" ]]; then
    # Re-running the script must not clobber local edits you haven't pushed.
    # To update an existing install, run `dotfiles pull` yourself.
    log_skip "$SECTION" "Install dotfiles" "already installed at ${DOTFILES_DIR}"
else
    run_cmd "$SECTION" "Clone dotfiles (bare)" \
        as_user git clone --bare "$DOTFILES_URL" "$DOTFILES_DIR"

    # `dotfiles status` would otherwise list EVERY file in your home dir.
    run_cmd "$SECTION" "Hide untracked files from dotfiles status" \
        dotgit config status.showUntrackedFiles no

    # A bare clone doesn't set up remote-tracking branches.  Without these
    # three steps, `dotfiles pull` and `dotfiles push` fail with
    # "no upstream branch".
    run_cmd "$SECTION" "Configure dotfiles fetch refspec" \
        dotgit config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    run_cmd "$SECTION" "Fetch dotfiles branches" \
        dotgit fetch -q origin
    DOTFILES_BRANCH="$(dotgit symbolic-ref --short HEAD)"
    run_cmd "$SECTION" "Track origin/${DOTFILES_BRANCH}" \
        dotgit branch -q --set-upstream-to="origin/${DOTFILES_BRANCH}" "$DOTFILES_BRANCH"

    # ls-tree lists every file path the repo tracks (e.g. .zshrc,
    # .local/bin/tmux-log-start).  For each one that already exists in ~,
    # move it into the backup dir, keeping its folder structure.
    while IFS= read -r file; do
        if [[ -e "${REAL_HOME}/${file}" || -L "${REAL_HOME}/${file}" ]]; then
            as_user mkdir -p "${BACKUP_DIR}/$(dirname "$file")"
            run_cmd "$SECTION" "Back up existing ~/${file}" \
                as_user mv "${REAL_HOME}/${file}" "${BACKUP_DIR}/${file}"
        fi
    done < <(dotgit ls-tree -r --name-only HEAD)

    run_cmd "$SECTION" "Check out dotfiles into ${REAL_HOME}" \
        dotgit checkout -q
fi

# ===========================================================================
# STEP 3: Install XFCE display settings
# ===========================================================================
#
# On a fresh Kali install, XFCE defaults to the panel's native resolution
# with no scaling.  On a HiDPI laptop (2880x1920), this makes everything
# tiny.  These config files restore our preferred scaling, resolution, and
# font settings.  They are Kali/XFCE-specific, so they live in THIS repo
# rather than the shared dotfiles repo.
#
# mkdir -p creates the directory AND any missing parents, with no error if
# it already exists.
XFCE_CONF_DIR="${REAL_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"

log_info "$SECTION" "Installing XFCE display settings..."

run_cmd "$SECTION" "Create XFCE config directory" \
    mkdir -p "$XFCE_CONF_DIR"

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
# STEP 4: Fix ownership of the XFCE files
# ===========================================================================
# Step 3 ran as root, so the files and any directories mkdir created are
# owned by root.  chown -R hands the whole tree back to the real user.
# (Step 2 ran git as the real user, so dotfiles are already owned correctly.)
run_cmd "$SECTION" "chown XFCE config directory" \
    chown -R "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.config/xfce4"

# ===========================================================================
# Summary
# ===========================================================================
log_info "$SECTION" "----------------------------------------------"
log_info "$SECTION" "Configs & dotfiles installation complete"
log_info "$SECTION" "----------------------------------------------"

print_summary
