## 1. Prerequisites

- Three Raspberry Pi 5 (I got [these](https://www.amazon.com/dp/B0FJ8GDZVM))
- Three SD cards (included in the kit I got)
- Willingness to suffer a little bit—hopefully lesser with this guide
- Fixed IP addresses for your Pi's. Fiddle around with your router DHCP config to achieve this reservation.

> [!WARNING] 
> **Very, VERY IMPORTANT**: If you're not wiring the Pi's, you'll face connectivity issues due to ARP black magic on WLAN interfaces—whether you use MetalLB, Cilium L2 announcements, or whatever the hell you run. We'll use Cilium here, and I can confirm I faced this issue where services would stop working randomly and only running a `tcpdump -ni ...` would restore connectivity. That's when I realized I couldn't be the only one, and indeed, more people are [impacted when using Wi-Fi](https://www.reddit.com/r/kubernetes/comments/1ns0g18/doing_k8s_labs_arp_issues_with_metallb/). You'll have to run `sudo ip link set wlan0 promisc on` in all the machines; you'll face VIPs that stop responding, leases that you'll need to manually kick, and cilium daemonsets you'll have to re-roll. No point in suffering this. **Please, make yourself a favor and use Ethernet.**

## 2. Prepping the Pi’s

Use the Raspberry Pi Imager to flash the SD card with a Raspberry Pi OS **Lite** (x64) as we’ll manage the cluster via ssh. We can avoid the **non-lite** version for this project, but feel free to install the base one if you want to play around with a mouse and keyboard. 

During the Imager setup you’ll be prompted to choose how to authenticate: choose ssh with pre-shared keys. Create the ssh key pair locally (note this is out of the scope for the sake of brevity but you’ll probably know how to find how to do it, if your memory fails you) and provide the public key path to the Imager. 

You’ll be able to flash as many SD cards as you want, just make sure you change the hostname every time a new card is inserted—this way you’ll be able to bootstrap every Pi with the same basic config (ssh, WiFi SSID, etc.). I do recommend to follow a nomenclature like “pi-001” so you can leverage a straightforward `~/.ssh/config` file like:

```
Host pi-*
    User <user-you-setup-with-pi-imager>
    IdentityFile C:\Users\<you>\.ssh\<your-private-key>
    IdentitiesOnly yes
```

Now you’ll be able to ssh into every machine. *You’re ready to start tweaking.*

You might as well run the following commands on your machines:

- `sudo apt update && sudo apt upgrade -y` — update local metadata index to know if your packages are up-to-date, then upgrade all of them with auto-approve
- `sudo apt autoremove` — removes all unnecessary or orphaned packages, useful for k8s as it lowers the risk of conflicting legacy networking packages, among other thingies


**WARNING**: Now there's something you need to know: `/boot/firmware/cmdline.txt` is the kernel command line used by the bootloader (no UEFI/BIOS here on Raspberrys). We need to edit this file (`sudo vi /boot/firmware/cmdline.txt`) by adding at the end—**NOT IN A NEW LINE**—the following string: `cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1`. Without this, `kubeadm init` will not work. Trust me, it won't.


### 2a. Memory swap

`kubeadm` does not like memory swap. There's been known issues before k8s v1.28.x and now you can configure kubelets to initiate even if swap is on, BUT, since we're talking about Raspberrys that hold SD cards for storage, then we better disable memory swap. It's worth noticing that with newer Raspberry OS, we have zram: an in-memory swap mechanism for compressing data before it gets send to disk; and we should also disable it just for maximum compatibility. Swap can be tolerated by modern kubernetes releases but that's still on beta so why bother? Let's play it safe.

Run `cat /etc/fstab | grep swap` — at the time of writing, this command outputs nothing; run `swapon --show` too and you'll get something like:
```
NAME       TYPE      SIZE USED PRIO
/dev/zram0 partition   2G   0B  100
```
This is expected because Pi OS is zram-based swap, not disk-backed (again, at the time of writing).
In order to fix this, you should disable swap by running `sudo swapoff /dev/zram0`

Another thing you can check:

```
$ systemctl list-unit-files | grep -i zram
rpi-zram-writeback.service                   static          -
systemd-zram-setup@.service                  static          -
dev-zram0.swap                               generated       -
rpi-zram-writeback.timer                     generated       -
```
From that list, you should know:
- systemd-zram-setup → Creates /dev/zram0 dynamically
- dev-zram0.swap → Activates it as swap
- rpi-zram-writeback.*→ Raspberry Pi–specific optimization (optional writeback behavior)

**This is auto-generated at boot, which is why `/etc/fstab` is empty**

swap reappears after reboot unless explicitly masked, so we will mask it to fix it for good. Run the following commands on your machines:
```
sudo systemctl mask dev-zram0.swap
sudo systemctl mask rpi-zram-writeback.timer
sudo systemctl mask rpi-zram-writeback.service
```
Now `sudo reboot` and go check if swap is enabled (`swapon --show`). 

### 2b. Networking

We'll use Cilium as our CNI (container network interface). This plugin is kind-of-a-leader amongst CNIs. Azure and other Cloud Providers are replacing whatever shit they have by Cilium. The idea is that the eBPF capabilities are leveraged and network traffic will stop relying on iptables in the future thereby routing via the good-ole' Linux kernel. Since I'm starting this project now, I figured to go straight to the shiny thing that will—allegedly—stay longer with us.

> WARNING: Now that we are talking about networking: make sure your Raspberrys always get the same IP address allocated, i.e., go into your router and fixate the DHCP address allocation so they always get the same one.

I will copy and paste some commands to ensure the kernel modules are in place (and changes are persisted after reboots). ChatGPT might have helped me here, or not. I'll leave that conclusion up to you 😊.


#### Persist and load kernel modules
```
sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<'EOF'
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```
#### Persist and apply sysctls
```
sudo tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<'EOF'
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system
```

#### Verify on any Pi
```
lsmod | egrep 'overlay|br_netfilter'
sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
```

Expected:

`overlay` and `br_netfilter` should appear.

all three sysctls return = 1

### 2c. Container Runtime Interface

Our CRI will be containerd. On all our machines, we'll run:
```
sudo apt update
sudo apt install -y containerd containernetworking-plugins
```

#### Default containerd config

Kubernetes requires an explicit config file. We will set some sane defaults in all 3 nodes via:

```
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
```
Now, in all 3 nodes run:
```
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl enable --now containerd
sudo systemctl restart containerd
```
At this point, we're ready to start setting up the Kubernetes cluster!

## 3. Setting the kubernetes cluster with kubeadm

We need to add the official Kubernetes apt repo (used to be different, now it's `pkgs.k8s.io`). This is explained [here](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#k8s-install-0) but we will tag along regardless.

### 3a. Add the k8s repository

Run on each node:
```
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gpg
```

Add the signing key:
```
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Add the repo:
```
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list
```

### 3b. Install the Kubernetes binaries

```
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
# And prevent unintended upgrades with this:
sudo apt-mark hold kubelet kubeadm kubectl
```

We'll also enable the kubelet, although it will crash-loop for now—at least until `kubeadm init` has run... patience!

```
sudo systemctl enable kubelet
# The command below will output some failures. Again: expected
sudo systemctl status kubelet
```

### 3c. Initializing the control plane

In your "control plane" Pi (most likely you'll have at least one, this guide will expand on what to do with the other control plane nodes), run `ip -4 addr show | grep -E "inet " | grep -v "127.0.0.1" && ip route | grep default` to get the address that we'll have to pass as the kube-apiserver for advertisement purposes. Once we get it, replace it in the following command, and run it:

```
sudo kubeadm init \
  --kubernetes-version v1.35.0 \
  --apiserver-advertise-address <put-your-master-node-ip> \
  --pod-network-cidr 10.244.0.0/16
```
> **Note:** `10.244.0.0/16` is a CIDR that is kind of conventional, but you don't have to necessarily use it. Just make sure your LAN network doesn't overlap with it. 

### 3d. Installing Helm

In your control plane Pi, you'll have to install Helm:
```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
```

And *verify* with: `helm version`.

Note we will install Helm in the cluster later. The binaries are installed now in the control plane node for 2 reasons: 
1. Easier to continue the following steps
2. Could be a helpful debugging tool, should any issues arise

### 3e. Installing Cilium

We add the repo first:
```
helm repo add cilium https://helm.cilium.io/
helm repo update
```
Now we install cilium in the control plane node (replace the IP address with the one used on step [3c](#3c-initializing-the-control-plane)):
```
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<put-your-master-node-ip> \
  --set k8sServicePort=6443 \
  --set cni.binPath=/usr/lib/cni \
  --set cni.confPath=/etc/cni/net.d \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="10.244.0.0/16" \
  --set ipam.operator.clusterPoolIPv4MaskSize=24
```
> *Note*: We are removing kube-proxy entirely (`--set kubeProxyReplacement=true`); Cilium handles service routing via eBPF.

At this point, you could run `kubectl -n kube-system delete ds kube-proxy && kubectl -n kube-system delete configmap kube-proxy`—this will delete redundant kube-proxy related resources that are not needed anymore.

### 3f. Join workers

In your master node, run `kubeadm token create --print-join-command` and copy and paste the result in your worker nodes (use `sudo`, obviously).

### 3g. Install the metrics-server component
```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml && \
kubectl -n kube-system patch deployment metrics-server \
  --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS"}
  ]'
```
Note we have patched with `--kubelet-insecure-tls`. metrics-server scrapes kubelets on port 10250, and the kubelets would include certificates for validation purposes. We are skipping that TLS setting for now. It's a home lab after all. But I'll probably work on this in the near future.

## 4. Validate

The first command will give you insights about cilium and the others will only work if the metrics server is running properly:
```
kubectl get ciliumnodes -o wide
kubectl top nodes
kubectl top pods -A | head
```

## 5. Misc
Run this command in your control plane node:
```
kubectl label node <worker-1-hostname> node-role.kubernetes.io/worker=worker
kubectl label node <worker-2-hostname> node-role.kubernetes.io/worker=worker
```

If you are using WLAN instead of wiring the Raspberrys, do this on every node:

```
sudo tee /etc/sysctl.d/99-cilium-rpfilter.conf <<'EOF'
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.wlan0.rp_filter=0
EOF

sudo sysctl --system
```
This will help avoiding some routing issues between your LAN devices and the control plane node. Specifically, by doing this, you disable reverse path filtering on a Wi-Fi interface, allowing Cilium’s NodePort return traffic to survive asymmetric routing after backend changes.

This is specially useful when you want to test connectivity (e.g., running a nginx webserver and hitting http://<any-node-ip-address>:<exposed-port> from your PC).

### 5a. ArgoCD

We will install ArgoCD using Helm.

```
kubectl create namespace argocd

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd

kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort"}}'

```

Now we login to ArgoCD from our PC by entering the IP address of any node and the specified port for argo (`kubectl get svc argocd-server -n argocd`) in our browser. Change the password and delete the secret from k8s: `kubectl -n argocd delete secret argocd-initial-admin-secret`.

### 5b. SealedSecrets

```
kubectl create namespace apps
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install sealed-secrets bitnami/sealed-secrets \
  -n kube-system
```
Verify:
```
kubectl -n kube-system get pods -l app.kubernetes.io/name=sealed-secrets
```

### If you need to create a sealed secret to commit to a repo
In your PC, run:
```
kubectl create secret generic <arbitrary-app-related-secrets> \
  --from-literal=KEY=VALUE \
  --dry-run=client -o yaml > secrets.plain.yaml
```
That will create a base64 encoded secret and display it to you without transmiting anything to the server (hence `--dry-run=client`). You cannot commit this to a repo, because you're not stupid. Let's use sealed secrets locally to seal it properly. Also in your PC, run:
```
choco/brew install sealed-secrets
```
```
kubeseal \
  --format yaml \
  --controller-name sealed-secrets \
  --controller-namespace kube-system \
  --namespace apps \
  < secrets.plain.yaml \
  > your-app/k8s/overlays/prod/sealedsecret-app-secret.yaml
```