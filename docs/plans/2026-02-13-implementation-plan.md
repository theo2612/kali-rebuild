# Kali Rebuild System - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a complete set of bash scripts that rebuild Brad's Kali pentest workstation from a fresh ISO install using a single `./install.sh` command.

**Architecture:** A main orchestrator script (`install.sh`) calls numbered scripts in order (01-08). Each script sources a shared logging library for consistent output. Package/tool lists live in separate text files so adding tools doesn't require editing scripts.

**Tech Stack:** Bash, apt, pipx, git, Docker Compose

---

### Task 1: Scaffold the repository structure

Create all directories and placeholder files so the repo shape is visible
from the start.

**Files:**
- Create: `~/kali-rebuild/.gitignore`
- Create: `~/kali-rebuild/scripts/` (directory)
- Create: `~/kali-rebuild/configs/` (directory)
- Create: `~/kali-rebuild/configs/apt/sources.list.d/` (directory)
- Create: `~/kali-rebuild/configs/bloodhound/` (directory)
- Create: `~/kali-rebuild/lists/` (directory)
- Create: `~/kali-rebuild/docs/` (already exists)
- Create: `~/kali-rebuild/README.md`

**Step 1: Create .gitignore**

```
# Runtime logs - never commit these
logs/

# OS junk
.DS_Store
*.swp
*~
```

**Step 2: Create directory structure**

```bash
mkdir -p ~/kali-rebuild/{scripts,configs/apt/sources.list.d,configs/bloodhound,lists,logs}
```

**Step 3: Create README.md**

A short README explaining what this repo is and how to use it. Two commands:
`git clone` then `./install.sh`. Point to the design doc and bash guide for
details.

**Step 4: Commit**

```bash
cd ~/kali-rebuild
git add .gitignore README.md
git commit -m "scaffold: add repo structure and README"
```

---

### Task 2: Build the shared logging library

This is the foundation every other script uses. It provides functions for
clean output, log file writing, and the summary system.

**Files:**
- Create: `~/kali-rebuild/scripts/lib.sh`

**Step 1: Write lib.sh with these functions**

The library must provide:
- `setup_logging` - creates timestamped log file in `~/kali-rebuild/logs/`,
  sets up the `LOGFILE` variable
- `log_info SECTION MESSAGE` - prints `[SECTION] MESSAGE...` to screen,
  writes full detail to log
- `log_ok SECTION MESSAGE` - prints green OK at end of line
- `log_fail SECTION MESSAGE` - prints red FAIL at end of line, records
  failure for summary
- `log_skip SECTION MESSAGE` - prints yellow SKIP at end of line
- `run_cmd SECTION MESSAGE COMMAND...` - runs a command, captures output to
  log, shows OK/FAIL on screen. This is the workhorse - most install steps
  use this.
- `print_header TITLE` - prints a boxed header for each script section
- `print_summary` - prints the end-of-run summary table with PASS/FAIL per
  section, duration, and manual steps remaining
- `ask_continue` - on failure, asks user "Continue or abort?"

Key bash concepts used (document in comments):
- Functions: `function_name() { ... }`
- Local variables: `local varname="value"`
- Exit codes: `$?` after a command (0 = success, anything else = failure)
- Redirects: `>> "$LOGFILE" 2>&1` to send stdout and stderr to log
- Colors: ANSI escape codes `\e[32m` (green), `\e[31m` (red), `\e[33m`
  (yellow), `\e[0m` (reset)
- Arrays: `FAILURES+=("message")` for tracking failures
- `printf` for aligned columns

**Step 2: Test the library manually**

```bash
source ~/kali-rebuild/scripts/lib.sh
setup_logging
log_info "test" "This is a test message"
log_ok "test" "This should be green"
log_fail "test" "This should be red"
run_cmd "test" "Listing home directory" ls ~/
run_cmd "test" "This should fail" false
print_summary
```

Verify: clean aligned output on screen, full output in log file.

**Step 3: Commit**

```bash
git add scripts/lib.sh
git commit -m "feat: add shared logging library (scripts/lib.sh)"
```

---

### Task 3: Create the package and tool list files

These are the data files that drive the install scripts. Separating data
from logic means adding a tool is just adding a line to a text file.

**Files:**
- Create: `~/kali-rebuild/lists/apt-packages.txt`
- Create: `~/kali-rebuild/lists/pipx-tools.txt`
- Create: `~/kali-rebuild/lists/bls-tools.txt`

**Step 1: Create apt-packages.txt**

This is the curated list - only packages you actually want installed beyond
a base Kali install. NOT the raw 449-package dump. Filter out:
- Base system packages (bash, coreutils, systemd, dpkg, etc.)
- Library packages (lib*)
- Kali meta-packages (kali-linux-core, kali-desktop-gnome, etc. - these
  come from the ISO installer)
- Packages that are dependencies of the above (they get pulled in
  automatically)
- `responder` (BLS fork used instead)

The list should contain actual pentest tools, utilities, and applications
you explicitly chose to install. Format: one package name per line, comments
with `#`.

Key packages to include (from audit):
```
# Pentest tools
aircrack-ng
amass
arp-scan
autopsy
binwalk
bloodhound
burpsuite
cewl
chntpw
commix
crunch
davtest
dirb
dirbuster
dnsenum
dnsrecon
evil-winrm
exploitdb
faraday
ffuf
fierce
gobuster
gophish
gpp-decrypt
hashcat
hashcat-utils
hashid
hping3
hydra
john
kismet
masscan
metasploit-framework
mimikatz
msfpc
nbtscan
ncrack
nikto
nmap
onesixtyone
passing-the-hash
peass
powershell
powershell-empire
powersploit
proxychains4
radare2
recon-ng
samba
skipfish
snmp
snmpcheck
socat
spiderfoot
spike
sqlmap
sslscan
sslyze
swaks
theharvester
wafw00f
webshells
weevely
wfuzz
whatweb
wifite
wireshark
wordlists
wpscan
zenmap
zmap

# Utilities
apache2
chromium
cifs-utils
creddump7
docker-compose
docker.io
dos2unix
golang
htop
libreoffice
mosh
neo4j
openvpn
php
pipx
python3-pip
python3-virtualenv
remmina
screen
signal-desktop
sqlitebrowser
sublime-text
terminator
tmux
tmux-plugin-manager
vim

# Build dependencies (needed for compiling some tools)
clang
libcurl4-openssl-dev
libnetfilter-queue-dev
libnfnetlink-dev
libnl-3-dev
libnl-genl-3-dev
libpcap-dev
libssl-dev
libusb-1.0-0-dev
nasm
python3-bs4
python3-lxml
python3-openssl
python3-requests
python3-scapy
zlib1g-dev
```

**Step 2: Create pipx-tools.txt**

Public tools (not BLS forks) installed via pipx. Format: one tool per line.

```
# Public Python tools - installed via pipx from PyPI
coercer
adidnsdump
```

**Step 3: Create bls-tools.txt**

BLS fork tools. Format: `repo-name|install-method|notes`

```
# BLS fork tools - installed from github.com/blacklanternsecurity
# Format: repo-name|install-method|notes
bbot|pipx|
bbot-server|pipx|
impacket|pipx|
certipy|pipx|check if repo name is certipy-ad
ldap_shell|pipx|
bad-secrets|pipx|
netexec|pipx|
webcap|pipx|
trevorspray|pipx|
responder|pipx|replaces apt version
itwasalladream|pipx|
pypykatz|pipx|
crackmapexec|pipx|
kerbrute|binary|Go binary - download from releases
```

**Step 4: Commit**

```bash
git add lists/
git commit -m "feat: add package and tool list files"
```

---

### Task 4: Create config files

Copy configs from the current machine into the repo structure.

**Files:**
- Create: `~/kali-rebuild/configs/zshrc` (from ~/.zshrc)
- Create: `~/kali-rebuild/configs/bashrc` (from ~/.bashrc)
- Create: `~/kali-rebuild/configs/profile` (from ~/.profile)
- Create: `~/kali-rebuild/configs/zprofile` (from ~/.zprofile)
- Create: `~/kali-rebuild/configs/gitconfig`
- Create: `~/kali-rebuild/configs/bloodhound/docker-compose.yml`
- Create: `~/kali-rebuild/configs/bloodhound/bloodhound.config.json`
- Create: `~/kali-rebuild/configs/apt/sources.list.d/neo4j.list`
- Create: `~/kali-rebuild/configs/apt/sources.list.d/signal-desktop.sources`
- Create: `~/kali-rebuild/configs/apt/sources.list.d/sublime-text.list`

**Step 1: Copy shell configs from current machine**

```bash
cp ~/.zshrc ~/kali-rebuild/configs/zshrc
cp ~/.bashrc ~/kali-rebuild/configs/bashrc
cp ~/.profile ~/kali-rebuild/configs/profile
cp ~/.zprofile ~/kali-rebuild/configs/zprofile
```

**Step 2: Create gitconfig**

```ini
[user]
    name = Brad Theodore
    email = brad.theodore@gmail.com
[init]
    defaultBranch = main
```

**Step 3: Copy BloodHound configs**

Copy `docker-compose.yml` from `~/bloodhound/`. Create a clean
`bloodhound.config.json` template (with a placeholder password that the
script will randomize on install - do NOT commit the real password).

**Step 4: Create apt source files**

Copy the three extra repo definitions:
- `neo4j.list` - Neo4j graph database
- `signal-desktop.sources` - Signal messenger
- `sublime-text.list` - Sublime Text editor

These go in `configs/apt/sources.list.d/`.

**Step 5: Commit**

```bash
git add configs/
git commit -m "feat: add config files (shell, git, bloodhound, apt repos)"
```

---

### Task 5: Write script 01-system-setup.sh

First script to run. Adds extra apt repositories, installs signing keys,
and runs apt update.

**Files:**
- Create: `~/kali-rebuild/scripts/01-system-setup.sh`

**Step 1: Write the script**

The script must:
1. Source `lib.sh` for logging functions
2. Print header: "Step 1 of 8: System Setup"
3. Add Neo4j apt repo + signing key
4. Add Signal Desktop apt repo + signing key
5. Add Sublime Text apt repo + signing key
6. Run `apt update`
7. Install base packages that other scripts depend on: `git`, `curl`,
   `wget`, `gpg`, `pipx`, `docker.io`, `docker-compose`
8. Run `pipx ensurepath`
9. Each step uses `run_cmd` for logging

Key signing key commands (from current machine):
- Neo4j: `wget -O- https://debian.neo4j.com/neotechnology.gpg.key | gpg --dearmor -o /etc/apt/keyrings/neo4j.gpg`
- Signal: already uses `/usr/share/keyrings/signal-desktop-keyring.gpg`
- Sublime: `wget -O- https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor -o /etc/apt/keyrings/sublimehq.gpg`

The script copies source files from `configs/apt/sources.list.d/` into
`/etc/apt/sources.list.d/`.

**Step 2: Make executable and test syntax**

```bash
chmod +x ~/kali-rebuild/scripts/01-system-setup.sh
bash -n ~/kali-rebuild/scripts/01-system-setup.sh
```

`bash -n` checks syntax without running the script. Should exit silently
(no errors).

**Step 3: Commit**

```bash
git add scripts/01-system-setup.sh
git commit -m "feat: add 01-system-setup.sh (apt repos and base packages)"
```

---

### Task 6: Write script 02-apt-tools.sh

Installs all pentest tools and utilities from apt.

**Files:**
- Create: `~/kali-rebuild/scripts/02-apt-tools.sh`

**Step 1: Write the script**

The script must:
1. Source `lib.sh`
2. Print header: "Step 2 of 8: APT Pentest Tools"
3. Read `lists/apt-packages.txt` line by line
4. Skip comment lines (starting with `#`) and empty lines
5. For each package, run `apt install -y PACKAGE`
6. Use `run_cmd` for each install so failures are logged individually
7. Count successes and failures for summary

Key bash concepts (document in comments):
- `while IFS= read -r line` - reading a file line by line
- Parameter expansion: `${line##\#*}` or `[[ "$line" =~ ^# ]]` - skip
  comments
- `continue` - skip to next loop iteration

**Step 2: Syntax check**

```bash
chmod +x ~/kali-rebuild/scripts/02-apt-tools.sh
bash -n ~/kali-rebuild/scripts/02-apt-tools.sh
```

**Step 3: Commit**

```bash
git add scripts/02-apt-tools.sh
git commit -m "feat: add 02-apt-tools.sh (apt package installation)"
```

---

### Task 7: Write script 03-pipx-tools.sh

Installs public Python tools via pipx.

**Files:**
- Create: `~/kali-rebuild/scripts/03-pipx-tools.sh`

**Step 1: Write the script**

The script must:
1. Source `lib.sh`
2. Print header: "Step 3 of 8: Public pipx Tools"
3. Ensure pipx is available (`command -v pipx`)
4. Read `lists/pipx-tools.txt` line by line
5. For each tool, run `pipx install TOOL`
6. Use `run_cmd` for each

**Step 2: Syntax check**

```bash
chmod +x ~/kali-rebuild/scripts/03-pipx-tools.sh
bash -n ~/kali-rebuild/scripts/03-pipx-tools.sh
```

**Step 3: Commit**

```bash
git add scripts/03-pipx-tools.sh
git commit -m "feat: add 03-pipx-tools.sh (public pipx tools)"
```

---

### Task 8: Write script 04-bls-tools.sh

Installs BLS fork tools from github.com/blacklanternsecurity.

**Files:**
- Create: `~/kali-rebuild/scripts/04-bls-tools.sh`

**Step 1: Write the script**

The script must:
1. Source `lib.sh`
2. Print header: "Step 4 of 8: BLS Tools"
3. Read `lists/bls-tools.txt` line by line
4. Parse the pipe-delimited format: `repo|method|notes`
5. For `pipx` method: `pipx install git+https://github.com/blacklanternsecurity/REPO.git`
6. For `binary` method (kerbrute): download latest release from GitHub
   releases page, make executable, place in `~/tools/kerbrute/`
7. Use `run_cmd` for each

Key bash concepts (document in comments):
- `IFS='|' read -r repo method notes` - splitting on a delimiter
- `case "$method" in pipx) ... ;; binary) ... ;; esac` - branching on
  install method

**Step 2: Syntax check**

```bash
chmod +x ~/kali-rebuild/scripts/04-bls-tools.sh
bash -n ~/kali-rebuild/scripts/04-bls-tools.sh
```

**Step 3: Commit**

```bash
git add scripts/04-bls-tools.sh
git commit -m "feat: add 04-bls-tools.sh (BLS fork installation)"
```

---

### Task 9: Write script 05-git-tools.sh

Clones standalone tools that aren't Python packages.

**Files:**
- Create: `~/kali-rebuild/scripts/05-git-tools.sh`

**Step 1: Write the script**

The script must:
1. Source `lib.sh`
2. Print header: "Step 5 of 8: Git-Clone Tools"
3. Create `~/tools/` directory
4. Clone any additional tools that aren't handled by apt, pipx, or BLS
   script (CVE exploits, standalone scripts, etc.)
5. Currently from the audit: CVE-2020-1472 (zerologon), bloodyAD,
   beanshooter, noPac, hawktrace
6. Use `run_cmd` for each clone

Note: Many of these may move to BLS tools or pipx over time. This script
is for anything that doesn't fit the other categories.

**Step 2: Syntax check and commit**

```bash
chmod +x ~/kali-rebuild/scripts/05-git-tools.sh
bash -n ~/kali-rebuild/scripts/05-git-tools.sh
git add scripts/05-git-tools.sh
git commit -m "feat: add 05-git-tools.sh (git clone tools)"
```

---

### Task 10: Write script 06-docker-services.sh

Sets up BloodHound CE via Docker Compose.

**Files:**
- Create: `~/kali-rebuild/scripts/06-docker-services.sh`

**Step 1: Write the script**

The script must:
1. Source `lib.sh`
2. Print header: "Step 6 of 8: Docker Services"
3. Create `~/bloodhound/` directory
4. Copy `docker-compose.yml` from configs
5. Generate a random password for `bloodhound.config.json` (using
   `openssl rand -base64 24`) - do NOT use the hardcoded one from the
   template
6. Create `bloodhound.config.json` with the random password
7. Run `docker compose pull`
8. Run `docker compose up -d`
9. Wait for healthy status (poll `docker compose ps` with timeout)
10. Print the generated admin password so the user can log in

Key bash concepts:
- Command substitution: `PASSWORD=$(openssl rand -base64 24)`
- Heredoc for creating the config JSON inline

**Step 2: Syntax check and commit**

```bash
chmod +x ~/kali-rebuild/scripts/06-docker-services.sh
bash -n ~/kali-rebuild/scripts/06-docker-services.sh
git add scripts/06-docker-services.sh
git commit -m "feat: add 06-docker-services.sh (BloodHound CE)"
```

---

### Task 11: Write script 07-configs.sh

Installs dotfiles and shell configurations.

**Files:**
- Create: `~/kali-rebuild/scripts/07-configs.sh`

**Step 1: Write the script**

The script must:
1. Source `lib.sh`
2. Print header: "Step 7 of 8: Configs & Dotfiles"
3. Copy shell configs: zshrc, bashrc, profile, zprofile
4. Copy gitconfig to `~/.gitconfig`
5. Each copy uses `run_cmd`

The script backs up existing configs before overwriting (e.g.,
`~/.zshrc` -> `~/.zshrc.bak`) in case this runs on a non-fresh system.

**Step 2: Syntax check and commit**

```bash
chmod +x ~/kali-rebuild/scripts/07-configs.sh
bash -n ~/kali-rebuild/scripts/07-configs.sh
git add scripts/07-configs.sh
git commit -m "feat: add 07-configs.sh (dotfiles and shell config)"
```

---

### Task 12: Write script 08-post-install.sh

Verifies everything installed correctly. The "did it actually work?" check.

**Files:**
- Create: `~/kali-rebuild/scripts/08-post-install.sh`

**Step 1: Write the script**

The script must:
1. Source `lib.sh`
2. Print header: "Step 8 of 8: Post-Install Verification"
3. Check each critical tool with `command -v`:
   - APT tools: nmap, hashcat, john, metasploit-framework (msfconsole),
     burpsuite, wireshark, sqlmap, gobuster, ffuf, hydra, nikto
   - pipx tools: coercer, adidnsdump
   - BLS tools: bbot, secretsdump.py, nxc/netexec, certipy, trevorspray,
     pypykatz, crackmapexec
   - Git tools: check directory exists for ~/tools/ items
   - Docker: `docker compose -f ~/bloodhound/docker-compose.yml ps`
   - Configs: verify ~/.zshrc, ~/.gitconfig exist
4. Count pass/fail
5. Call `print_summary` with all results
6. Print manual steps reminder:
   - Activate BurpSuite license
   - Install Bitwarden Firefox extension
   - Log into Signal Desktop
   - Generate SSH keys if needed

**Step 2: Syntax check and commit**

```bash
chmod +x ~/kali-rebuild/scripts/08-post-install.sh
bash -n ~/kali-rebuild/scripts/08-post-install.sh
git add scripts/08-post-install.sh
git commit -m "feat: add 08-post-install.sh (verification and summary)"
```

---

### Task 13: Write the main install.sh orchestrator

The entry point that ties everything together.

**Files:**
- Create: `~/kali-rebuild/install.sh`

**Step 1: Write install.sh**

The script must:
1. Check it's running as root (many apt/docker commands need sudo). If not,
   print a message and re-exec with sudo.
2. Set `REPO_DIR` to the directory where install.sh lives (so it works
   regardless of where you `cd` from)
3. Source `lib.sh`
4. Call `setup_logging`
5. Print the main banner
6. Run each script in order: 01 through 08
7. If any script exits non-zero and user chooses abort, stop
8. Call `print_summary` at the end

Key bash concepts:
- `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` - finding
  the script's own directory
- `source` vs `bash` - sourcing shares variables, running as subprocess
  doesn't
- `$EUID` - checking if running as root

**Step 2: Make executable and syntax check**

```bash
chmod +x ~/kali-rebuild/install.sh
bash -n ~/kali-rebuild/install.sh
```

**Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh main orchestrator"
```

---

### Task 14: Write the bash learning guide

The companion document that explains bash concepts using the actual scripts
as examples.

**Files:**
- Create: `~/kali-rebuild/docs/bash-guide.md`

**Step 1: Write the guide**

Cover each concept from the design doc with examples pulled directly from
the scripts we just wrote:
- Variables and quoting
- if/then/else and exit codes
- for loops and while read loops
- Functions
- Piping and redirects
- Arrays
- Command substitution
- set -e and set -o pipefail
- Common patterns: `command -v`, `|| true`, heredocs

Each section: short explanation, then "Here's where you see this in your
scripts:" with the actual code block.

**Step 2: Commit**

```bash
git add docs/bash-guide.md
git commit -m "docs: add bash learning guide"
```

---

### Task 15: Final integration test and push

Verify everything works together before pushing to GitHub.

**Step 1: Run syntax check on all scripts**

```bash
for f in ~/kali-rebuild/install.sh ~/kali-rebuild/scripts/*.sh; do
    echo "Checking $f..."
    bash -n "$f" && echo "  OK" || echo "  FAIL"
done
```

All should pass.

**Step 2: Dry-run review**

Read through install.sh and each script to verify:
- lib.sh is sourced with correct path
- List files are referenced with correct paths
- Config files are copied from correct paths
- All scripts are executable

**Step 3: Create private GitHub repo and push**

```bash
cd ~/kali-rebuild
gh repo create kali-rebuild --private --source=. --push
```

**Step 4: Final commit if any fixes needed**

```bash
git add -A
git commit -m "chore: final cleanup before first push"
git push
```

---

## Execution Order Summary

| Task | What | Depends On |
|------|------|-----------|
| 1 | Scaffold repo | Nothing |
| 2 | Logging library (lib.sh) | Task 1 |
| 3 | Package/tool list files | Task 1 |
| 4 | Config files | Task 1 |
| 5 | 01-system-setup.sh | Task 2 |
| 6 | 02-apt-tools.sh | Task 2 |
| 7 | 03-pipx-tools.sh | Task 2 |
| 8 | 04-bls-tools.sh | Task 2 |
| 9 | 05-git-tools.sh | Task 2 |
| 10 | 06-docker-services.sh | Task 2, 4 |
| 11 | 07-configs.sh | Task 2, 4 |
| 12 | 08-post-install.sh | Task 2 |
| 13 | install.sh orchestrator | Tasks 5-12 |
| 14 | Bash learning guide | Tasks 5-12 |
| 15 | Integration test + push | All |

Tasks 3 and 4 can run in parallel. Tasks 5-12 can partially parallelize
(they all depend on Task 2 but not on each other).
