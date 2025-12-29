## Usage

- Scripts from `10-os.sh` up to (and including) `60-k8s-packages.sh` are going to be used on all nodes as they prepare your nodes for kubernetes in Raspberry Pi OS
- Scripts 70, 80, 90 and 99 are to be run in the control plane only (pi-001 in my case)
- Script 71 should be used on worker nodes only (pi-002 and pi-003 in my case)


## Examples
One host, many stages:
```
bash run.sh pi-004 10-os 20-cgroups 30-swapoff 40-net 50-containerd 60-k8s-packages
```
One host, one stage: 
```
bash run.sh pi-002 30-swapoff
```

“Worker join” only:
```
bash run.sh pi-004 71-kubeadm-join
```