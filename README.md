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
vagrant ssh master -c "sudo bash /vagrant/install-apps.sh"
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

\## Manual Installation (Alternative)

If you prefer to run the apps installation from within the master node:

```bash
vagrant ssh master
sudo bash /vagrant/install-apps.sh
```

