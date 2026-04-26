\# Install Vagrant on Windows

```bash
winget install Hashicorp.Vagrant
```

\# Install VirtualBox if not already installed

\## Quick Start

\### 1. Create the Kubernetes cluster

```bash
vagrant up
```

This will:
- Create master and worker nodes
- Initialize Kubernetes control plane
- Install Calico CNI
- Join worker to the cluster

\### 2. Install Istio, Helm, and Harbor (after cluster is ready)

```bash
vagrant provision master --provision-with install-apps
```

This will:
- Wait for all nodes to be ready
- Download and install Istio (ambient mode)
- Install Helm
- Install Gateway API CRDs
- Deploy Istio Gateway
- Install Harbor registry
- Configure HTTPRoute for Harbor

\## Verify Installation

```bash
\# Get a shell into master
vagrant ssh master

\# Check cluster status
kubectl get nodes
kubectl get pods -n istio-system
kubectl get pods -n harbor
```

\## Harbor Registry

Harbor is deployed and accessible via Istio Gateway:

- **URL**: http://192.168.56.10/harbor
- **Username**: admin
- **Password**: Harbor12345

Login from your host machine:

```bash
docker login 192.168.56.10/harbor
```

\## Cluster Lifecycle (Shutdown & Resume)

### Suspend / Resume (recommended)

Saves the exact VM memory state. The cluster comes back as-is with no restart required.

```bash
vagrant suspend   # before shutting down your machine
vagrant resume    # after powering back on
```

### Halt / Up

Clean shutdown. All k8s control plane components (kubelet, etcd, apiserver) are registered as systemd services and will auto-start on `vagrant up`.

```bash
vagrant halt      # before shutting down your machine
vagrant up        # after powering back on
```

Wait ~60s after `vagrant up` for the cluster to fully initialize, then verify:

```bash
kubectl get nodes
kubectl get pods -n istio-system
```

> **Note:** `vagrant suspend` is safer than `vagrant halt` — if etcd doesn't start cleanly after a halt, the cluster can get stuck.

### Snapshot (save a known-good state)

Take a snapshot once the cluster and Istio ambient mode are fully configured:

```bash
vagrant snapshot save "cluster-ready"      # save baseline
vagrant snapshot restore "cluster-ready"   # roll back if needed
```

## Manual Installation (Alternative)

If you prefer to run the apps installation from within the master node:

```bash
vagrant ssh master
sudo bash /vagrant/install-apps.sh
```

