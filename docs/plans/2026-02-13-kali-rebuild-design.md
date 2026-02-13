# Kali Rebuild System - Design Document

**Date:** 2026-02-13
**Author:** Brad Theodore + Claude
**Status:** Approved

---

## Purpose

Create a set of bash scripts stored in a private GitHub repo that can rebuild
a fully configured Kali Linux pentest workstation from a fresh ISO install.
The system must be fast, reliable, and educational (scripts serve as bash
learning material).

## Context

- **Machine:** Framework 13 laptop, Kali 2025.4 Rolling, 868GB disk
- **User:** Pentester at Black Lantern Security (BLS)
- **Workflow:** Fresh Kali install after each engagement, clone repo, run
  install script, machine is ready
- **Employer tools:** 14 BLS-forked tools on github.com/blacklanternsecurity
- **Learning goal:** Build bash scripting skills through commented scripts
  and a companion guide

## Decisions Made

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Approach | Bash scripts (not Ansible/Nix) | Learn bash first, no bootstrap deps, right scope for one machine |
| Storage | Private GitHub repo | Survives OS wipe, version controlled, accessible from fresh install |
| BLS tools | All from github.com/blacklanternsecurity | Company forks with custom modifications |
| Python tools | pipx (not pip, not manual venvs) | Automatic isolation per tool, no venv management, no dependency conflicts |
| Configs with client data | Excluded from repo | BurpSuite projects, NetExec creds, BBOT scans, SSH known_hosts - none stored |
| Error handling | Clean status lines + full log file + summary | Not a wall of text; failures are obvious and debuggable |
| Learning | Commented scripts + separate bash-guide.md | Scripts are self-documenting; guide covers patterns used |

---

## Repository Structure

```
kali-rebuild/
├── install.sh                  # Main entry point - orchestrates everything
├── scripts/
│   ├── 01-system-setup.sh      # Apt repos, system packages, base config
│   ├── 02-apt-tools.sh         # Pentest tools available via apt
│   ├── 03-pipx-tools.sh        # Public Python tools via pipx
│   ├── 04-bls-tools.sh         # BLS fork tools from GitHub
│   ├── 05-git-tools.sh         # Other git-clone tools (CVE exploits, etc.)
│   ├── 06-docker-services.sh   # BloodHound CE, any other containers
│   ├── 07-configs.sh           # Dotfiles, shell config, tool configs
│   └── 08-post-install.sh      # Final checks, verification, cleanup
├── configs/
│   ├── zshrc                   # Zsh config
│   ├── bashrc                  # Bash config
│   ├── profile                 # Login profile
│   ├── zprofile                # Zsh login profile
│   ├── gitconfig               # Git user config
│   ├── bloodhound/
│   │   └── docker-compose.yml  # BloodHound CE compose file
│   └── apt/
│       └── sources.list.d/     # Extra apt repos (neo4j, signal, sublime)
├── lists/
│   ├── apt-packages.txt        # APT packages to install (one per line)
│   ├── pipx-tools.txt          # Public pipx tools (one per line)
│   └── bls-tools.txt           # BLS repos with install method
├── docs/
│   ├── bash-guide.md           # Bash concepts used in these scripts
│   ├── tool-notes.md           # Notes on individual tools, gotchas
│   └── plans/                  # Design documents (like this one)
├── logs/                       # Created at runtime, gitignored
└── README.md                   # How to use this repo
```

### Why numbered scripts

Scripts run in dependency order. APT repos (01) must exist before apt
tools (02). pipx must be installed (02 installs it) before pipx tools
(03/04). Docker must be installed (02) before services (06).

Each script can also be run independently for debugging or partial rebuilds.

---

## Tool Installation Strategy

### Tier 1: APT packages (system-level tools)

Tools maintained by Kali's package team. If it's in apt and we don't need
a custom fork, use apt.

**Examples:** nmap, hashcat, john, metasploit-framework, burpsuite, wireshark,
tmux, docker.io, docker-compose, golang, vim, git

**Source file:** `lists/apt-packages.txt`

**Note:** `responder` is available via apt but we use the BLS fork instead.
The apt-tools script skips packages that appear in `bls-tools.txt` to avoid
conflicts.

### Tier 2: pipx for Python tools (isolated environments)

pipx creates an invisible virtual environment per tool. Each tool gets its
own isolated Python with its own dependencies. No conflicts. No manual venv
activation. Commands land in `~/.local/bin/` and just work.

**Public tools (script 03):**
- coercer
- adidnsdump

**Source file:** `lists/pipx-tools.txt`

**BLS fork tools (script 04):**
- bbot
- bbot-server
- impacket
- certipy
- ldap_shell
- bad-secrets
- netexec
- webcap
- trevorspray
- responder
- itwasalladream
- pypykatz
- crackmapexec

**Install method for BLS forks:**
```bash
pipx install git+https://github.com/blacklanternsecurity/REPONAME.git
```

**Source file:** `lists/bls-tools.txt`

### Tier 3: Git clone (non-Python tools, exploit scripts)

Tools that aren't Python packages - Go binaries, standalone scripts,
exploit PoCs. Cloned into `~/tools/` organized by name.

**Examples:** kerbrute (Go binary), CVE exploit scripts

**Install method:** Clone repo, build if needed (e.g., `go build` for
kerbrute), verify binary exists.

### Tier 4: Docker services

Multi-container applications managed by Docker Compose.

**BloodHound CE:** bloodhound + neo4j + postgres
- Compose file stored in `configs/bloodhound/docker-compose.yml`
- Script copies it to `~/bloodhound/`, runs `docker compose up -d`
- Waits for healthy status before continuing

---

## Configuration Management

### Configs stored in repo (no client data)

| File | Source | Destination |
|------|--------|-------------|
| `configs/zshrc` | Repo | `~/.zshrc` |
| `configs/bashrc` | Repo | `~/.bashrc` |
| `configs/profile` | Repo | `~/.profile` |
| `configs/zprofile` | Repo | `~/.zprofile` |
| `configs/gitconfig` | Repo | `~/.gitconfig` |
| `configs/bloodhound/docker-compose.yml` | Repo | `~/bloodhound/docker-compose.yml` |
| `configs/apt/sources.list.d/*` | Repo | `/etc/apt/sources.list.d/` |

### Configs NOT stored (contain/may contain engagement data)

| Config | Why excluded | Rebuild action |
|--------|-------------|----------------|
| BurpSuite (`~/.BurpSuite/`) | Project history, client URLs | Installed via apt; manual license activation |
| NetExec (`~/.nxc/`) | Credentials, target data | Fresh default created on first run |
| BBOT (`~/.bbot/`) | Scan configs with client targets | Fresh default on first run |
| Firefox profile | Browsing history, saved logins | Fresh profile; note to install Bitwarden |
| SSH keys/known_hosts | Client host fingerprints | Generate new keys if needed |
| BloodHound data volumes | Client AD data | Fresh empty database on docker compose up |

---

## Error Handling and Logging

### On-screen output

Clean, single-line status per action:
```
[04-bls-tools]  Installing bbot (blacklanternsecurity)...     OK
[04-bls-tools]  Installing impacket...                        FAIL
```

### Log file

Full verbose output written to `~/kali-rebuild/logs/YYYY-MM-DD_HH-MM-SS.log`.
On failure, the log line number is referenced in the summary.

### Failure behavior

When a step fails:
1. Red FAIL shown on screen
2. Script asks: "Continue to next item or abort?"
3. Failure recorded for summary

### End-of-run summary

```
══════════════════════════════════════════
  Install Summary
══════════════════════════════════════════
  01 System Setup       PASS
  02 APT Tools          PASS  (47 packages)
  03 pipx Tools         PASS  (6 tools)
  04 BLS Tools          FAIL  (bbot - see log line 847)
  05 Git Tools          PASS  (1 tool)
  06 Docker Services    PASS  (3 containers)
  07 Configs            PASS
  08 Verification       PASS  (23/24 tools found)

  Log: ~/kali-rebuild/logs/2026-02-13_14-30-00.log
  Duration: 12m 34s

  Manual steps remaining:
  - Activate BurpSuite license
  - Install Bitwarden Firefox extension
  - Log into Signal Desktop
  - Set up SSH keys if needed
══════════════════════════════════════════
```

---

## Post-Install Verification

Script 08 checks that every tool is actually reachable:
- APT tools: `command -v toolname` or `which toolname`
- pipx tools: `command -v toolname` (checks ~/.local/bin/)
- Git tools: Verify binary/script exists at expected path
- Docker services: Check `docker compose ps` shows healthy containers
- Configs: Verify files exist at destination paths

---

## Rebuild Workflow

### On engagement teardown day:
1. Pull engagement data off the machine (reports, loot, evidence)
2. Wipe: fresh Kali install from ISO

### On rebuild day:
```bash
# Step 1: Clone the repo (git is already on fresh Kali)
git clone https://github.com/YOUR_USERNAME/kali-rebuild.git ~/kali-rebuild

# Step 2: Run the install
cd ~/kali-rebuild && ./install.sh

# Step 3: Manual steps (5 minutes)
# - Activate BurpSuite license
# - Install Bitwarden in Firefox
# - Log into Signal
# - Generate SSH keys if needed
```

### Maintaining the repo (during normal use):
```bash
# Added a new apt tool:
echo "gobuster" >> ~/kali-rebuild/lists/apt-packages.txt

# Changed shell config:
cp ~/.zshrc ~/kali-rebuild/configs/zshrc

# Commit and push:
cd ~/kali-rebuild && git add -A && git commit -m "added gobuster" && git push
```

---

## Bash Learning Guide

A separate `docs/bash-guide.md` covers these patterns, using the actual
scripts as examples:

| Concept | Where it appears | What it does |
|---------|-----------------|--------------|
| Variables | Everywhere | `LOGFILE="install.log"` |
| if/then/else | Error checking | "Did that command succeed?" |
| for loops | Package lists | "Do this for every line in the file" |
| Exit codes (`$?`) | After every install | How bash knows success vs failure |
| Functions | Logging helpers | `log_ok()`, `log_fail()` |
| Piping (`\|`) | Filtering output | Send output of one command into another |
| Redirects (`>`, `>>`, `2>&1`) | Logging | Send output to files |
| `command -v` | Verification | "Is this tool installed?" |
| `set -e`, `set -o pipefail` | Script headers | "Stop if something fails" |
| Reading files line by line | Package lists | Processing txt files |

---

## Future Additions

- **pentest-coach skill:** Claude Code skill at github.com/theo2612/ctf-pentest-coach.
  Will be added once the repo is updated. Install script section for Claude Code
  plugin setup.
- **Ansible migration:** Once comfortable with bash, the scripts can be
  translated to Ansible playbooks for more robust state management.
- **Engagement data script:** A separate `wipe-engagement.sh` for quick data
  cleanup between engagements that don't require full rebuild (if workflow
  changes).

---

## What This System Does NOT Do

- Store credentials, API keys, or client data
- Manage BurpSuite licensing (manual activation required)
- Back up engagement artifacts (separate process)
- Handle disk encryption setup (done during Kali install)
- Manage VPN configurations (client-specific, per engagement)
