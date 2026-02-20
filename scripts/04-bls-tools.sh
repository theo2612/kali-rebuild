#!/usr/bin/env bash
# ===========================================================================
# 04-bls-tools.sh -- Install BLS (Black Lantern Security) fork tools
# ===========================================================================
#
# This script reads lists/bls-tools.txt and installs tools from the
# Black Lantern Security GitHub organisation.  BLS maintains forks of
# popular security tools with patches, fixes, and improvements that
# have not yet been merged upstream.
#
# WHY INSTALL FROM git+URL?
#   Running `pipx install "git+https://github.com/blacklanternsecurity/REPO.git"`
#   installs the BLS *fork* directly from source.  If you ran
#   `pipx install REPO` instead, pip would pull the upstream (public PyPI)
#   version, which would not include BLS-specific patches.  The git+URL
#   syntax tells pip to clone the repo and install from the cloned source.
#
# BASH CONCEPTS COVERED
#   - Reading a file line-by-line with a while loop and IFS
#   - Custom field splitting with IFS='|'
#   - Here-strings (<<<) to feed a variable as stdin
#   - The case...esac statement for multi-branch conditionals
#   - Arithmetic with $(( )) for counting successes/failures
# ===========================================================================

# Exit immediately on error (-e), treat unset variables as errors (-u),
# and fail a pipeline if any command in it fails (-o pipefail).
set -euo pipefail

# ---- Source the shared library ---------------------------------------------
# "$(dirname "$0")" resolves to the directory this script lives in (scripts/),
# so lib.sh is always found regardless of where the user calls the script from.
source "$(dirname "$0")/lib.sh"

# ---- Initialise logging and print header -----------------------------------
setup_logging
print_header "BLS Tools"

# ---- Configuration ---------------------------------------------------------
# BLS_ORG is the base URL for the Black Lantern Security GitHub organisation.
# All repos in bls-tools.txt are assumed to live under this org.
BLS_ORG="https://github.com/blacklanternsecurity"

# Path to the tool list file.  REPO_DIR is set by lib.sh and points to the
# top-level directory of this repository.
TOOLS_FILE="${REPO_DIR}/lists/bls-tools.txt"

# ---- Determine the real user ------------------------------------------------
# This script runs as root (via sudo), but pipx tools should be installed for
# the real user, not root.  sudo -u runs commands as the specified user.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# Initialise this section so it appears in the summary table.
SECTION_RESULTS["BLS"]="PASS"

# ---- Verify the tool list exists -------------------------------------------
if [[ ! -f "$TOOLS_FILE" ]]; then
    log_fail "BLS" "Tool list not found: ${TOOLS_FILE}"
    print_summary
    exit 1
fi

# ---- Ensure ~/tools/ exists for clone method --------------------------------
mkdir -p "${REAL_HOME}/tools"

# ---- Counters for the summary ---------------------------------------------
success_count=0
fail_count=0
skip_count=0

# ---- Read and process each line --------------------------------------------
# We read the file line-by-line using a while loop.  The `|| true` at the end
# ensures the loop processes the last line even if the file does not end with
# a newline (without it, `read` returns non-zero on EOF and the last line
# would be silently dropped).
while IFS= read -r line || [[ -n "$line" ]]; do

    # --- Skip blank lines ---------------------------------------------------
    # -z tests whether the string is empty (zero length).
    [[ -z "$line" ]] && continue

    # --- Skip comment lines -------------------------------------------------
    # The pattern #* matches any string that starts with '#'.
    [[ "$line" == \#* ]] && continue

    # --- Parse the pipe-delimited fields ------------------------------------
    # IFS='|' read -r repo method notes <<< "$line"
    #
    #   IFS='|'    -- temporarily sets the Internal Field Separator to the pipe
    #                 character.  This tells `read` to split the input on '|'
    #                 instead of the default whitespace.  The change only
    #                 affects this single `read` command.
    #
    #   read -r    -- reads one line of input and splits it into variables.
    #                 -r prevents backslash interpretation (so a literal \n in
    #                 the input stays as \n, not a newline).
    #
    #   repo method notes  -- three variable names that receive the three
    #                         pipe-separated fields.  If there are fewer fields,
    #                         the extra variables are set to empty strings.
    #
    #   <<< "$line"  -- a HERE-STRING.  It feeds the contents of $line to the
    #                   command's stdin as if you had typed it and pressed Enter.
    #                   This is more concise than `echo "$line" | read ...` and
    #                   avoids the subshell that a pipe would create (which
    #                   would make the variables invisible outside the pipe).
    IFS='|' read -r repo method notes <<< "$line"

    # Trim any stray whitespace from the parsed fields.
    repo="${repo// /}"
    method="${method// /}"

    log_info "BLS" "Installing ${repo} (method: ${method})${notes:+ -- ${notes}}"

    # --- Branch on install method using a case statement --------------------
    # case...esac is bash's equivalent of a switch statement.  Each pattern
    # ends with ')' and the corresponding block ends with ';;'.  The '*)' arm
    # is the default (catch-all), like 'default:' in C/Go/etc.
    case "$method" in

        pipx)
            # Install the BLS fork via pipx.  The git+URL format tells pip to
            # clone the repository and install it, rather than looking the
            # package up on PyPI.  This ensures we get the BLS fork, not the
            # upstream/public version.
            if run_cmd "BLS" "pipx install ${repo}" \
                sudo -u "$REAL_USER" pipx install "git+${BLS_ORG}/${repo}.git"; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
            ;;

        clone)
            # Some BLS tools are not pip-installable Python packages.  For
            # these we clone the repo into ~/tools/<repo>/ and run them
            # directly from the source tree.
            #
            # We clone as root (simpler than sudo -u with git) and then
            # chown the directory to the real user afterward.
            local clone_dir="${REAL_HOME}/tools/${repo}"
            if [[ -d "$clone_dir" ]]; then
                log_skip "BLS" "Clone ${repo}" "already exists"
                skip_count=$((skip_count + 1))
            elif run_cmd "BLS" "Clone ${repo}" \
                git clone "${BLS_ORG}/${repo}.git" "$clone_dir"; then
                # Fix ownership so the real user can modify the cloned files.
                chown -R "${REAL_USER}:${REAL_USER}" "$clone_dir"
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
            ;;

        *)
            # Unknown install method -- skip this entry so we do not crash.
            log_skip "BLS" "${repo}" "unknown install method '${method}'"
            skip_count=$((skip_count + 1))
            ;;
    esac

done < "$TOOLS_FILE"

# ---- Summary ---------------------------------------------------------------
log_info "BLS" "----------------------------------------------"
log_info "BLS" "BLS Tools complete: ${success_count} succeeded, ${fail_count} failed, ${skip_count} skipped"
log_info "BLS" "----------------------------------------------"

print_summary
