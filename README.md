# kali-rebuild

Bash scripts to rebuild a fully configured Kali Linux pentest workstation from a
fresh ISO install. Built for a Framework 13 laptop running Kali Rolling.

After a fresh Kali install, two commands get the machine back to a working state:

```bash
git clone git@github.com:<your-user>/kali-rebuild.git ~/kali-rebuild
cd ~/kali-rebuild && sudo ./install.sh
```

The install script handles everything: apt packages, pentest tools, dotfiles,
shell configuration, and system settings. Failures are logged and summarized at
the end so you know exactly what needs attention.

## Repository layout

```
scripts/          # Individual installer scripts (called by install.sh)
configs/          # Config files deployed to the system
lists/            # Package and tool lists (one item per line)
docs/             # Design doc and bash guide
logs/             # Runtime logs (git-ignored)
```

## Documentation

- [Design document](docs/plans/2026-02-13-kali-rebuild-design.md) -- architecture
  decisions, tool inventory, and repo structure
- Bash guide (coming soon) -- patterns and techniques used in the scripts
