# Raspberry Pi 5 — SD → NVMe Migration (Clean Runbook)

A safe, repeatable procedure to migrate a Raspberry Pi 5 node from **microSD** to **NVMe SSD** using a HAT, avoiding live-clone drift and Kubernetes instability.

---

## Assumptions

- Raspberry Pi 5 with NVMe HAT installed
- NVMe disk visible as `/dev/nvme0n1`
- SD card visible as `/dev/mmcblk0`
- Root filesystem is partition `p2`
- Boot firmware partition is `p1`
- Kubernetes cluster (optional, but steps include it)
- One node migrated at a time

---

## 0. Pre-flight checks

```bash
lsblk
```

Confirm:
- `mmcblk0` → SD card
- `nvme0n1` → NVMe SSD

---

## 1. Quiesce the node (avoid filesystem drift)

### From a control node (if using Kubernetes)

```bash
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force
```

### On the node being migrated

```bash
sudo systemctl stop kubelet
sudo systemctl stop containerd
```

---

## 2. Clone SD → NVMe (detached, resilient)

```bash
sudo sh -c 'nohup dd if=/dev/mmcblk0 of=/dev/nvme0n1 bs=4M conv=fsync status=progress > /var/log/dd-nvme.log 2>&1 &'
```

Monitor progress:

```bash
sudo tail -f /var/log/dd-nvme.log
```

Wait until you see the final summary:

```
XXXX+Y records in
XXXX+Y records out
<bytes> copied, <time>, <speed>
```

---

## 3. Filesystem check on NVMe (offline)

Ensure NVMe is **not mounted**:

```bash
mount | grep nvme && sudo umount /dev/nvme0n1p2
```

Run fsck:

```bash
sudo e2fsck -f /dev/nvme0n1p2
```

Answer `y` to any fixes.

---

## 4. Catch-up sync (recommended)

### Mount NVMe root and boot

```bash
sudo mkdir -p /mnt/nvme-root
sudo mount /dev/nvme0n1p2 /mnt/nvme-root

sudo mkdir -p /mnt/nvme-root/boot/firmware
sudo mount /dev/nvme0n1p1 /mnt/nvme-root/boot/firmware
```

### Rsync root filesystem

```bash
sudo rsync -aHAXx --numeric-ids --delete   --exclude={"/dev/*","/proc/*","/sys/*","/run/*","/tmp/*","/mnt/*","/media/*","/lost+found"}   / /mnt/nvme-root/
```

### Rsync boot firmware

```bash
sudo rsync -aHAX --delete /boot/firmware/ /mnt/nvme-root/boot/firmware/
sync
```

### Unmount

```bash
sudo umount /mnt/nvme-root/boot/firmware
sudo umount /mnt/nvme-root
```

---

## 5. Expand NVMe root filesystem

```bash
sudo parted /dev/nvme0n1 resizepart 2 100%
sudo e2fsck -f /dev/nvme0n1p2
sudo resize2fs /dev/nvme0n1p2
```

---

## 6. Set boot order to NVMe

```bash
sudo raspi-config
```

Navigate:

```
Advanced Options → Boot Order → NVMe / USB Boot
```

---

## 7. Cut over to NVMe

```bash
sudo shutdown -h now
```

- Remove the SD card
- Power on the Pi

Verify:

```bash
lsblk
cat /proc/cmdline
```

Confirm `/` is mounted from `nvme0n1p2`.

---

## 8. Re-enable services and rejoin cluster

```bash
sudo systemctl start containerd
sudo systemctl start kubelet
kubectl uncordon <node>
```

---

## 9. Post-migration SSD hygiene (per node)

```bash
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer
sudo sed -i 's/relatime/noatime/' /etc/fstab
```

Reboot when convenient to apply mount options.

---

## Notes

- Always migrate **one node at a time**
- Use `nohup` or `tmux` for long-running operations
- Stopping kubelet/containerd before cloning avoids live-write drift
- NVMe dramatically reduces containerd and etcd corruption risk compared to SD
