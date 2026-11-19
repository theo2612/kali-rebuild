# Kali Installer GUI Checklist

Step-by-step walkthrough of the Kali Linux graphical installer. Use this
for both VM testing and bare-metal installs on the Framework 13.

## Installer Steps

1. **Boot** -- Select **"Graphical Install"**
2. **Language** -- **English**
3. **Location** -- **United States**
4. **Keyboard** -- **American English**
5. **Hostname** -- **bls-wopr** (or your preferred name)
6. **Domain** -- leave **blank**
7. **Full name** -- **Brad Theodore**
8. **Username** -- **theo**
9. **Password** -- set your user password
10. **Timezone** -- **Eastern**
11. **Partition disks** -- select **"Partition disks"** from the menu
12. **Partitioning method** -- **"Guided - use entire disk and set up encrypted LVM"**
13. **Select disk** -- pick the **internal drive** (NOT the USB)
    - Bare metal: `NVMe - WD_BLACK SN850X` (or similar)
    - VM: `Virtual disk 1 (vda)`
14. **Partition scheme** -- **"All files in one partition"**
15. **Write changes to disk?** -- **Yes**
16. **Erasing data** -- wait for it to finish
17. **LUKS passphrase** -- set your encryption passphrase (you type this at every boot)
18. **Volume group size** -- **max** (accept the default)
19. **Review layout** -- **"Finish partitioning and write changes to disk"**
20. **Confirm write changes** -- **Yes**
21. **Software selection** -- keep defaults: **Xfce + top10 + default tools**
22. **GRUB boot loader** -- install to the **internal drive** (NOT the USB)
    - Bare metal: `/dev/nvme0n1`
    - VM: `/dev/vda`
23. **Installation complete** -- **Continue** to reboot
24. **Remove USB** (bare metal: pull it out; VM: fix boot order in virt-manager)
25. **LUKS passphrase prompt** -- enter your encryption passphrase
26. **Login screen** -- enter username and password

## Run the Rebuild

```bash
git clone https://github.com/theo2612/kali-rebuild.git ~/kali-rebuild
cd ~/kali-rebuild && sudo ./install.sh
```

## Notes

- On bare metal, use F2 (or F12) during boot to access BIOS/boot menu if
  the system doesn't automatically boot from the NVMe after removing the USB.
- The encrypted LVM option creates three partitions: `/boot` (unencrypted),
  root `/` (encrypted), and swap (encrypted).
- The "All files in one partition" scheme is recommended for workstations.
  Separate `/home` or `/var` partitions are a server concern.
