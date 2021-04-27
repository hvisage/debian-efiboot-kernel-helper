# debian-efiboot-kernel-helper
Debian based scripts to assist in efi only kernel booting

All the credit should go to ProxMox as this is forked from https://git.proxmox.com/?p=pve-kernel-meta.git;a=summary
fallback: https://git.proxmox.com/git/pve-kernel-meta.git

I've whacked things in place for a standard Debian ZFS on root setup to "work"

bugs are mine and mine alone... take a ticket and stand in line for firing squad membership, else send a PR please ;)

```
sudo -i
rm zfs-root.sh; wget https://apt.tros.ovh/scripts/zfs-root.sh ; chmod +x zfs-root.sh ; ./zfs-root.sh
```

need to investigate:

```
 update-initramfs: Generating /boot/initrd.img-4.19.0-16-amd64
I: The initramfs will attempt to resume from /dev/nvme0n1p3
I: (UUID=d5172291-69f6-49eb-892b-4abb0f10b9b6)
I: Set the RESUME variable to override this.
```