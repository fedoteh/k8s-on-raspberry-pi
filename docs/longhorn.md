On all nodes:
```bash
sudo apt-get update
sudo apt-get install -y open-iscsi nfs-common cryptsetup dmsetup
sudo modprobe iscsi_tcp
sudo systemctl enable --now iscsid
systemctl status iscsid --no-pager
sudo mkdir -p /var/lib/longhorn
sudo chmod 700 /var/lib/longhorn
```


On the master/control-plane node:
```bash
curl -sSfL -o longhornctl https://github.com/longhorn/cli/releases/download/v1.10.1/longhornctl-linux-arm64
chmod +x longhornctl
kubectl create namespace longhorn-system
./longhornctl check preflight --kubeconfig=~/.kube/config
```

If the preflight checks throw these errors:

```bash
fedoteh@PI-001:~/.kube $ ./longhornctl check preflight --kubeconfig=config
INFO[2026-01-25T21:50:47-03:00] Initializing preflight checker
INFO[2026-01-25T21:50:47-03:00] Cleaning up preflight checker
INFO[2026-01-25T21:50:47-03:00] Running preflight checker
INFO[2026-01-25T21:50:50-03:00] Retrieved preflight checker result:
pi-002:
  error:
  - '[KernelModules] nfs is not loaded. (exit code: 1)'
  - '[KernelModules] dm_crypt is not loaded. (exit code: 1)'
  info:
  - '[KubeDNS] Kube DNS "coredns" is set with 2 replicas and 2 ready replicas'
  - '[IscsidService] Service iscsid is running'
  - '[MultipathService] multipathd.service is not found (exit code: 4)'
  - '[MultipathService] multipathd.socket is not found (exit code: 4)'
  - '[NFSv4] NFS4 is supported'
  - '[Packages] nfs-common is installed'
  - '[Packages] open-iscsi is installed'
  - '[Packages] cryptsetup is installed'
  - '[Packages] dmsetup is installed'
pi-003:
  error:
  - '[KernelModules] nfs is not loaded. (exit code: 1)'
  - '[KernelModules] dm_crypt is not loaded. (exit code: 1)'
  info:
  - '[KubeDNS] Kube DNS "coredns" is set with 2 replicas and 2 ready replicas'
  - '[IscsidService] Service iscsid is running'
  - '[MultipathService] multipathd.service is not found (exit code: 4)'
  - '[MultipathService] multipathd.socket is not found (exit code: 4)'
  - '[NFSv4] NFS4 is supported'
  - '[Packages] nfs-common is installed'
  - '[Packages] open-iscsi is installed'
  - '[Packages] cryptsetup is installed'
  - '[Packages] dmsetup is installed'
INFO[2026-01-25T21:50:50-03:00] Cleaning up preflight checker
INFO[2026-01-25T21:50:50-03:00] Completed preflight checker
```

dm_crypt is fixable by persisting it across reboots by running this on your worker nodes:
```bash
sudo modprobe dm_mod
sudo modprobe dm_crypt

cat <<'EOF' | sudo tee /etc/modules-load.d/longhorn.conf
dm_mod
dm_crypt
EOF

sudo systemctl restart systemd-modules-load

# Verify
lsmod | egrep -i '^(dm_crypt|dm_mod)\b' || true
```

On the other hand, the Longhorn preflight error `[KernelModules] nfs is not loaded` is a false positive for the kernel build: there is no nfs module to load because NFS client support is compiled in.
RaspiOS shenanigans... You can safely proceed.

WIP...