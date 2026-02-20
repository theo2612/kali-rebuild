# kali-rebuild

Bash scripts to rebuild a fully configured Kali Linux pentest workstation from a
fresh ISO install. Built for a Framework 13 laptop running Kali Rolling.

## Full rebuild steps

1. **Flash the Kali ISO to USB**
   - Download the latest installer from https://www.kali.org/get-kali/#kali-installer
   - Flash it to a USB drive:
     ```bash
     sudo dd if=kali-linux-*.iso of=/dev/sdX bs=4M status=progress
     ```
     Replace `/dev/sdX` with your USB device (check with `lsblk`). On macOS/Windows, use [Balena Etcher](https://etcher.balena.io/).

2. **Install Kali** -- Boot from USB, run the graphical installer. Use default partitioning or encrypted LVM for work machines.

3. **Run the rebuild** -- Boot into your fresh Kali desktop, open a terminal:
   ```bash
   git clone https://github.com/theo2612/kali-rebuild.git ~/kali-rebuild
   cd ~/kali-rebuild && sudo ./install.sh
   ```

4. **Complete manual steps** -- The script prints a checklist at the end (BurpSuite license, SSH keys, etc.).

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
