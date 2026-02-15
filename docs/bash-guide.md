# Bash Scripting Guide -- Learn From Your Own Scripts

This guide explains every bash concept used in your kali-rebuild scripts.
Every example is pulled directly from scripts you wrote, so by the end you
will understand every line of your own code.

---

## 1. The Shebang Line

The very first line of every script tells your operating system which
interpreter to use when you run the file.

```bash
#!/usr/bin/env bash
```

- `#!` is called the **shebang** (or hashbang). The kernel reads it and
  launches the specified program to interpret the rest of the file.
- `/usr/bin/env bash` means "find `bash` wherever it is on this system."
  This is more portable than hardcoding `/bin/bash` because bash lives in
  different locations on different distros and on macOS.

**From every script in the project** (e.g. `scripts/lib.sh` line 1):

```bash
#!/usr/bin/env bash
```

Without the shebang, running `./install.sh` would fall back to `/bin/sh`,
which is a smaller, less featureful shell. Features like `[[ ]]`, arrays,
and `set -o pipefail` would break.

---

## 2. Strict Mode (`set -euo pipefail`)

Every install script starts with this line immediately after the shebang.
It catches bugs early instead of letting them snowball.

```bash
set -euo pipefail
```

**From `scripts/01-system-setup.sh` (line 25):**

```bash
set -euo pipefail
```

What each flag does:

| Flag | Effect |
|------|--------|
| `-e` | Exit immediately if ANY command returns a non-zero exit code. Without this, a failing command is silently ignored and the script keeps running -- potentially in a broken state. |
| `-u` | Treat references to unset variables as errors. Catches typos: `$NAEM` would silently expand to an empty string without this. |
| `-o pipefail` | In a pipeline (`cmd1 \| cmd2`), bash normally reports only the exit code of the LAST command. With pipefail, the pipeline fails if ANY command in it fails. Critical when you pipe `wget` into `gpg`. |

**Quick demo** -- without `-u`, this silently does nothing:

```bash
echo "$NAEM"   # prints empty string, no error
```

With `-u`, you get an error: `NAEM: unbound variable`.

---

## 3. Variables and Quoting

### Assignment

No spaces around the `=`. This is a syntax rule, not a style choice.

```bash
SECTION="APT"               # correct
SECTION = "APT"             # WRONG -- bash thinks SECTION is a command
```

**From `scripts/02-apt-tools.sh` (line 70):**

```bash
SECTION="APT"
PACKAGE_LIST="${REPO_DIR}/lists/apt-packages.txt"
```

### Double Quotes vs Single Quotes

| Syntax | Variables expand? | Use when... |
|--------|:-:|---|
| `"hello $USER"` | Yes | You want variable values substituted |
| `'hello $USER'` | No | You want the literal string `$USER` |
| `hello $USER` | Yes | Risky -- word splitting and globbing can bite you |

**Rule of thumb:** Always double-quote your variables. `"$VAR"` is almost
always what you want. Unquoted variables break on spaces, tabs, and
wildcards.

```bash
file="my report.txt"
cat $file       # WRONG -- bash sees two args: "my" and "report.txt"
cat "$file"     # correct -- bash sees one arg: "my report.txt"
```

**From `scripts/lib.sh` (line 55) -- double quotes protect the path:**

```bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

---

## 4. Parameter Expansion

Bash can manipulate variable values inline without calling external tools.

### Default Values: `${VAR:-default}`

If `VAR` is unset or empty, use `default` instead.

**From `scripts/05-git-tools.sh` (line 103):**

```bash
REAL_USER="${SUDO_USER:-$USER}"
```

This means: use `SUDO_USER` if set (running under sudo); otherwise fall
back to `$USER`. It makes the script work with and without sudo.

### Strip a Pattern from the End: `${VAR%%pattern}`

**From `scripts/02-apt-tools.sh` (line 106):**

```bash
line="${line%%#*}"
```

`%%#*` removes the longest match of `#*` (a `#` followed by anything)
from the END of the string. This strips inline comments:

```
Input:  "nmap  # port scanner"
Result: "nmap  "
```

| Syntax | Meaning |
|--------|---------|
| `${VAR%pattern}` | Remove shortest match from END |
| `${VAR%%pattern}` | Remove longest match from END |
| `${VAR#pattern}` | Remove shortest match from FRONT |
| `${VAR##pattern}` | Remove longest match from FRONT |

### Array Length: `${#array[@]}`

**From `scripts/lib.sh` (line 326):**

```bash
local fail_count=${#FAILURES[@]}
```

The `#` prefix means "length of". `[@]` means "all elements". So
`${#FAILURES[@]}` gives the number of items in the `FAILURES` array.

---

## 5. Conditionals: `if` / `then` / `else`

### Exit Codes Are Everything

In bash, `if` does not check "true" or "false". It runs a **command** and
checks the **exit code**:

- `0` = success (the condition is "true")
- non-zero = failure (the condition is "false")

Every command returns an exit code. `$?` holds the most recent one.

**From `scripts/lib.sh` (line 233-234) -- capturing an exit code:**

```bash
"$@" >> "$LOGFILE" 2>&1
exit_code=$?
```

### The `[[ ]]` Test Command

`[[ ]]` is a bash built-in for evaluating conditions. Always prefer it
over the older `[ ]` because:

- It handles empty variables safely (no need for extra quoting tricks).
- It supports `&&`, `||`, regex (`=~`), and pattern matching natively.
- It does not do word splitting or glob expansion on variables.

**Common test operators:**

| Operator | Meaning | Example |
|----------|---------|---------|
| `-f FILE` | File exists and is a regular file | `[[ -f "$target" ]]` |
| `-d PATH` | Directory exists | `[[ -d "$tool_dir" ]]` |
| `-z STRING` | String is empty (zero length) | `[[ -z "$line" ]]` |
| `-n STRING` | String is non-empty | `[[ -n "$line" ]]` |
| `-eq` | Integer equality | `[[ $exit_code -eq 0 ]]` |

**From `scripts/08-post-install.sh` (lines 163-167) -- the `check_cmd` function:**

```bash
check_cmd() {
    local tool="$1"

    if command -v "$tool" &>/dev/null; then
        log_ok "$SECTION" "${tool} found"
    else
        log_fail "$SECTION" "${tool} NOT found"
    fi
}
```

**From `scripts/07-configs.sh` (line 183) -- checking if a file exists
before backing it up:**

```bash
if [[ -f "$target_file" ]]; then
    run_cmd "$SECTION" "Backup .${config}" \
        cp "$target_file" "${target_file}.bak"
else
    log_info "$SECTION" "No existing .${config} to back up"
fi
```

---

## 6. Loops

### `while IFS= read -r line` -- Read a File Line by Line

This is the standard pattern for processing a text file line by line.

**From `scripts/02-apt-tools.sh` (lines 101-146):**

```bash
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    # ...process the line...
    continue    # skip to next iteration (used for blank lines)
done < "$PACKAGE_LIST"
```

Breaking it down:

| Piece | Purpose |
|-------|---------|
| `IFS=` | Set Internal Field Separator to empty so leading/trailing whitespace is preserved |
| `read -r` | Raw mode -- do not interpret backslash escapes (`\n` stays literal) |
| `line` | Variable that receives each line |
| `\|\| [[ -n "$line" ]]` | Handle files without a trailing newline -- without this, the last line is silently skipped |
| `< "$PACKAGE_LIST"` | Redirect the file into the loop's stdin |

### `for item in "${array[@]}"` -- Iterate Over an Array

**From `scripts/07-configs.sh` (lines 156-194):**

```bash
SHELL_CONFIGS=("zshrc" "bashrc" "profile" "zprofile")

for config in "${SHELL_CONFIGS[@]}"; do
    source_file="${REPO_DIR}/configs/${config}"
    target_file="${REAL_HOME}/.${config}"
    # ...backup and copy logic...
done
```

`"${SHELL_CONFIGS[@]}"` expands to every element, each properly quoted.

### C-Style `for` Loop -- Iterate by Index

**From `scripts/05-git-tools.sh` (lines 188-222):**

```bash
tool_count=${#TOOL_NAMES[@]}

for (( i=0; i<tool_count; i++ )); do
    name="${TOOL_NAMES[$i]}"
    url="${TOOL_URLS[$i]}"
    tool_dir="${TOOLS_DIR}/${name}"

    if [[ -d "$tool_dir" ]]; then
        log_skip "$SECTION" "Clone ${name}" "already exists"
    else
        run_cmd "$SECTION" "Clone ${name}" \
            sudo -u "$REAL_USER" git clone "$url" "$tool_dir"
    fi
done
```

This is the cleanest way to walk two parallel arrays by index.

### `break` and `continue`

- `continue` -- skip the rest of the current iteration, jump to the next.
- `break` -- exit the loop entirely.

**From `scripts/02-apt-tools.sh` (line 114):**

```bash
if [[ -z "${local_trimmed// /}" ]]; then
    continue    # blank line -- skip to the next one
fi
```

---

## 7. Functions

### Defining a Function

```bash
function_name() {
    # body
}
```

**From `scripts/lib.sh` (lines 160-167):**

```bash
log_ok() {
    local section="$1"
    local message="$2"

    printf "  %-55s ${GREEN}OK${RESET}\n" "[${section}]  ${message}"
    _write_log "OK" "$section" "$message"
}
```

### `local` Variables

`local` restricts a variable to the function scope. Without it, the
variable leaks into the caller's environment and can overwrite things.

```bash
run_cmd() {
    local section="$1"       # only visible inside run_cmd
    local message="$2"
    local exit_code          # declared local, assigned later
    # ...
}
```

### Arguments: `$1`, `$2`, `shift`

- `$1` is the first argument, `$2` the second, and so on.
- `shift N` discards the first N arguments. After `shift 2`, what was `$3`
  becomes `$1`.

**From `scripts/lib.sh` (lines 217-219) -- `run_cmd` uses `shift` so
`$@` becomes just the command:**

```bash
run_cmd() {
    local section="$1"
    local message="$2"
    shift 2   # remove section and message; now $@ = the command to run

    "$@" >> "$LOGFILE" 2>&1    # execute whatever is left
}
```

### Return Values vs Exit Codes

Functions use `return N` (not `exit N`) to set their exit code. `exit`
would kill the entire script. The caller checks the return value with `$?`
or an `if` statement.

**From `scripts/lib.sh` (line 246):**

```bash
return $exit_code
```

---

## 8. Arrays

### Indexed Arrays

Declared with parentheses. Zero-based indexing.

**From `scripts/lib.sh` (line 78):**

```bash
FAILURES=()                       # empty array
FAILURES+=("APT: nmap failed")    # append an element
echo "${FAILURES[0]}"             # access first element
echo "${#FAILURES[@]}"            # number of elements
```

**From `scripts/05-git-tools.sh` (lines 149-163) -- parallel arrays:**

```bash
TOOL_NAMES=(
    "CVE-2020-1472"
    "bloodyAD"
    "beanshooter"
)

TOOL_URLS=(
    "https://github.com/dirkjanm/CVE-2020-1472"
    "https://github.com/CravateRouge/bloodyAD"
    "https://github.com/qtc-de/beanshooter"
)
```

Same index `i` maps a name to its URL.

### Associative Arrays (Dictionaries)

Declared with `declare -A`. Keys are strings, not integers.

**From `scripts/lib.sh` (lines 83-84):**

```bash
declare -A SECTION_RESULTS

SECTION_RESULTS["APT"]="PASS"
SECTION_RESULTS["DOCKER"]="FAIL"

# Iterate over keys:
for section in "${!SECTION_RESULTS[@]}"; do
    echo "$section -> ${SECTION_RESULTS[$section]}"
done
```

Note: `${!ARRAY[@]}` (with `!`) gives the **keys**. `${ARRAY[@]}`
(without `!`) gives the **values**.

### Quick Reference

| Operation | Syntax |
|-----------|--------|
| Create indexed | `ARR=("a" "b" "c")` |
| Create associative | `declare -A MAP` |
| Append | `ARR+=("new")` |
| Access element | `${ARR[0]}` or `${MAP["key"]}` |
| All elements | `"${ARR[@]}"` |
| All keys | `"${!ARR[@]}"` |
| Length | `${#ARR[@]}` |

---

## 9. Piping and Redirects

### Pipe: `|`

Sends stdout of one command into stdin of the next.

**From `scripts/01-system-setup.sh` (line 83) -- download a key and
convert it in one step:**

```bash
bash -c 'wget -qO- https://debian.neo4j.com/neotechnology.gpg.key | gpg --dearmor -o /etc/apt/keyrings/neo4j.gpg'
```

`wget` downloads the key to stdout, `gpg` reads it from stdin and writes
the binary version to a file.

### Redirects

| Syntax | Meaning |
|--------|---------|
| `> file` | Write stdout to file (overwrite) |
| `>> file` | Append stdout to file |
| `2>&1` | Merge stderr (fd 2) into stdout (fd 1) |
| `&>/dev/null` | Silence everything (stdout + stderr to the black hole) |
| `< file` | Feed file contents into stdin |

**From `scripts/lib.sh` (line 233) -- run a command, capture ALL output
to the log:**

```bash
"$@" >> "$LOGFILE" 2>&1
```

- `>> "$LOGFILE"` appends stdout to the log file.
- `2>&1` merges stderr into stdout, so both go to the log.
- The screen stays clean.

**From `scripts/08-post-install.sh` (line 163) -- silence everything:**

```bash
if command -v "$tool" &>/dev/null; then
```

We only care about the exit code, not the output, so we throw it all away.

---

## 10. Command Substitution

`$(command)` runs `command` in a subshell, captures its stdout, and
replaces itself with that output.

### Simple examples from the scripts

**From `scripts/lib.sh` (line 109) -- capture the current timestamp:**

```bash
timestamp="$(date '+%Y%m%d-%H%M%S')"
```

**From `scripts/06-docker-services.sh` (line 152) -- generate a random
password:**

```bash
BH_PASSWORD=$(openssl rand -base64 24)
```

### Nested command substitution

**From `scripts/lib.sh` (line 55) -- find the repo root directory:**

```bash
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

Reading inside-out:

1. `${BASH_SOURCE[0]}` -- path of this file (e.g. `/home/brad/kali-rebuild/scripts/lib.sh`)
2. `dirname "${BASH_SOURCE[0]}"` -- directory part (`/home/brad/kali-rebuild/scripts`)
3. `cd ".../scripts/.."` -- move up one level to the repo root
4. `pwd` -- print the absolute path (`/home/brad/kali-rebuild`)
5. The outer `$()` captures that path into `REPO_DIR`.

---

## 11. Special Variables

| Variable | Meaning | Example from scripts |
|----------|---------|----------------------|
| `$?` | Exit code of the last command (0 = success) | `exit_code=$?` in `lib.sh` line 234 |
| `$@` | All arguments passed to the script or function | `"$@" >> "$LOGFILE" 2>&1` in `lib.sh` line 233 |
| `$0` | Name/path of the current script | `$(dirname "$0")/lib.sh` in every script |
| `$1`, `$2`... | Positional arguments | `local section="$1"` in `lib.sh` functions |
| `$EUID` | Effective user ID (0 = root) | Used in `install.sh` to check for root |
| `BASH_SOURCE[0]` | Path of the file being sourced or executed | `lib.sh` line 44 source guard |
| `SECONDS` | Seconds since the shell started (or since you reset it) | `SECONDS=0` in `lib.sh` line 114, read in `print_summary` |
| `SUDO_USER` | The real user who ran `sudo` | `REAL_USER="${SUDO_USER:-$USER}"` in `05-git-tools.sh` |

### `$@` vs `$*`

- `"$@"` -- each argument stays as a separate word (what you almost always want).
- `"$*"` -- all arguments joined into a single string.

**From `scripts/lib.sh` (line 233):**

```bash
"$@" >> "$LOGFILE" 2>&1
```

After `shift 2`, `$@` contains the command and its arguments. `"$@"`
preserves each argument as a separate word, so `apt-get install -y vim`
is passed as four separate arguments, not one string.

---

## 12. Common Patterns

### Check If a Tool Is Installed: `command -v`

**From `scripts/03-pipx-tools.sh` (line 74):**

```bash
if ! command -v pipx &>/dev/null; then
    log_fail "PIPX" "pipx is not installed"
    exit 1
fi
```

Prefer `command -v` over `which` because:
- `command` is a bash built-in (always available, no external dependency).
- `which` is an external program whose behaviour varies across distros.
- `command -v` also finds shell functions and aliases.

### Prevent `set -e` From Killing the Script: `|| true`

When you use `set -e`, any failing command kills the script. If you
EXPECT a command might fail and want to handle it yourself, append
`|| true`:

```bash
run_cmd "$SECTION" "BloodHound containers running" \
    docker compose -f "${BH_DIR}/docker-compose.yml" ps || true
```

The `||` (OR) operator runs the right side only if the left side fails.
Since `true` always succeeds, the overall exit code is 0 and `set -e`
does not trigger. An `if` statement also prevents `set -e` from firing:

```bash
if run_cmd "$SECTION" "Install ${package}" apt-get install -y "$package"; then
    (( success_count++ ))
else
    (( fail_count++ ))
fi
```

### Here-Strings: `<<<`

Feed a variable's value directly into a command's stdin.

**From `scripts/04-bls-tools.sh` (line 96):**

```bash
IFS='|' read -r repo method notes <<< "$line"
```

This splits `$line` on the `|` character into three variables. The
here-string (`<<<`) avoids a pipe (`echo "$line" | read ...`), which
would run `read` in a subshell where the variables would be invisible
to the rest of the script.

### Here-Documents: `<<EOF`

Feed multiple lines of text into a command. Used less in these scripts,
but good to know:

```bash
cat <<EOF
Hello, $USER
Today is $(date)
EOF
```

Variables and command substitutions ARE expanded inside `<<EOF`. Use
`<<'EOF'` (quoted) to prevent expansion.

### Source Guard

Prevents a library file from being run directly. If someone types
`./scripts/lib.sh` instead of `source scripts/lib.sh`, the guard
catches it.

**From `scripts/lib.sh` (lines 44-48):**

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi
```

- `BASH_SOURCE[0]` is the path of the file currently being read.
- `$0` is the script that was originally invoked.
- When sourced, these differ (lib.sh vs 01-system-setup.sh).
- When run directly, they are the same (both lib.sh), so the guard fires.

### `case` / `esac` -- Multi-Branch Conditionals

Bash's version of a switch statement.

**From `scripts/04-bls-tools.sh` (lines 108-146):**

```bash
case "$method" in
    pipx)
        pipx install "git+${BLS_ORG}/${repo}.git"
        ;;
    binary)
        # download binary release...
        ;;
    *)
        log_skip "BLS" "${repo}" "unknown method '${method}'"
        ;;
esac
```

- Each pattern ends with `)`.
- Each block ends with `;;`.
- `*)` is the default/catch-all (like `default:` in other languages).

### Idempotent Scripts (Check Before Acting)

A script is idempotent if running it twice produces the same result as
running it once. Check whether work is already done before doing it.

**From `scripts/05-git-tools.sh` (lines 200-201):**

```bash
if [[ -d "$tool_dir" ]]; then
    log_skip "$SECTION" "Clone ${name}" "already exists"
else
    run_cmd "$SECTION" "Clone ${name}" \
        sudo -u "$REAL_USER" git clone "$url" "$tool_dir"
fi
```

### Arithmetic: `(( ))`

**From `scripts/02-apt-tools.sh` (line 130):**

```bash
(( total_count++ ))
```

Inside `(( ))`, you can use C-style operators without `$` on variable
names:

```bash
(( count++ ))                 # increment
(( total = pass + fail ))     # addition
(( remaining = total - done ))
```

You can also use `$(( ))` to capture the result:

```bash
total=$((success_count + fail_count + skip_count))
```

---

## Tips for Pentesters

### Running Scripts as Root vs Regular User

Many security tools need root to install (apt, systemctl, usermod), but
you do NOT want your working files owned by root. The kali-rebuild
scripts solve this with `SUDO_USER`:

```bash
REAL_USER="${SUDO_USER:-$USER}"
sudo -u "$REAL_USER" git clone "$url" "$tool_dir"
```

The script runs as root (for installs) but clones repos as the real user
(so you own the files).

### When to Use `bash -c` vs Direct Commands

`run_cmd` in lib.sh passes arguments directly to the command. This works
great for simple commands:

```bash
run_cmd "APT" "Update cache" apt-get update -qq
```

But when you need shell features like pipes (`|`) or redirects (`>`),
those only work inside a shell. Wrap the whole thing in `bash -c`:

```bash
run_cmd "SYS-SETUP" "Download Neo4j signing key" \
    bash -c 'wget -qO- https://debian.neo4j.com/neotechnology.gpg.key | gpg --dearmor -o /etc/apt/keyrings/neo4j.gpg'
```

Without `bash -c`, the `|` would be interpreted by `run_cmd`'s own shell
context incorrectly.

### Debugging: `bash -x` to Trace Execution

Run any script with `-x` to see every command before it executes:

```bash
bash -x ./scripts/02-apt-tools.sh
```

Output looks like:

```
+ set -euo pipefail
+ source /home/brad/kali-rebuild/scripts/lib.sh
++ REPO_DIR=/home/brad/kali-rebuild
+ setup_logging
+ SECTION=APT
```

Each `+` line shows the command after variable expansion. `++` means the
command came from a sourced file or subshell. This is invaluable when a
script fails and you cannot figure out where.

You can also add `set -x` inside a script temporarily to trace just a
specific section:

```bash
set -x        # start tracing
some_command
another_command
set +x        # stop tracing
```

### Shellcheck for Linting

[ShellCheck](https://www.shellcheck.net/) is a static analysis tool that
catches common bash mistakes before you run the script:

```bash
# install it
sudo apt-get install shellcheck

# check a script
shellcheck scripts/02-apt-tools.sh
```

It catches things like:
- Unquoted variables that will break on spaces
- Useless uses of `cat`
- Variables used before assignment
- POSIX compatibility issues

You can also paste scripts into https://www.shellcheck.net/ in your
browser.

---

## Quick Reference Card

```
VARIABLES
  VAR="value"                   Assignment (no spaces around =)
  "$VAR"                        Always double-quote (prevents word splitting)
  ${VAR:-default}               Use default if VAR is unset/empty
  ${VAR%%pattern}               Strip longest match of pattern from end
  ${#VAR}                       Length of string
  ${#ARR[@]}                    Number of elements in array

CONDITIONALS
  if [[ -f file ]]; then        File exists
  if [[ -d dir ]]; then         Directory exists
  if [[ -z "$str" ]]; then      String is empty
  if [[ -n "$str" ]]; then      String is non-empty
  if command -v tool &>/dev/null  Tool is installed

LOOPS
  for item in "${ARR[@]}"; do   Loop over array elements
  for (( i=0; i<n; i++ )); do  C-style counting loop
  while IFS= read -r line; do  Read file line by line
    done < file

REDIRECTS
  > file                        Overwrite file with stdout
  >> file                       Append stdout to file
  2>&1                          Merge stderr into stdout
  &>/dev/null                   Silence all output
  <<< "$var"                    Here-string (feed var to stdin)

FUNCTIONS
  fname() { ... }               Define a function
  local var="$1"                Function-scoped variable
  return 0                      Set function exit code
  shift N                       Discard first N arguments

SPECIAL VARIABLES
  $?        last exit code      $@        all arguments
  $0        script name         $1..$9    positional args
  $EUID     effective user ID   SECONDS   elapsed seconds
  BASH_SOURCE[0]                current file path
```
