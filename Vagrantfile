ENV['VAGRANT_NO_PARALLEL'] = 'yes'   # ← forces master first, then worker

MASTER_IP = "192.168.56.10"
WORKER_IP = "192.168.56.11"

COMMON_SCRIPT = <<~SHELL
  set -e

  echo "=== Disabling swap ==="
  swapoff -a
  sed -i '/ swap / s/^/#/' /etc/fstab

  echo "=== Loading kernel modules ==="
  modprobe overlay
  modprobe br_netfilter
  echo "overlay" > /etc/modules-load.d/k8s.conf
  echo "br_netfilter" >> /etc/modules-load.d/k8s.conf

  echo "=== Sysctl params ==="
  echo "net.bridge.bridge-nf-call-iptables  = 1" > /etc/sysctl.d/k8s.conf
  echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/k8s.conf
  echo "net.ipv4.ip_forward                 = 1" >> /etc/sysctl.d/k8s.conf
  sysctl --system

  echo "=== Bringing up enp0s8 ==="
  ip link set enp0s8 up || true

  echo "=== Installing containerd ==="
  apt-get update -y
  apt-get install -y containerd apt-transport-https ca-certificates curl gpg
  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl restart containerd
  systemctl enable containerd

  echo "=== Installing kubelet kubeadm kubectl ==="
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
    > /etc/apt/sources.list.d/kubernetes.list
  apt-get update -y
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
  systemctl enable kubelet

  echo "=== Common setup done ==="
SHELL

MASTER_SCRIPT = <<~SHELL
  set -e

  echo "=== Assigning master IP to enp0s8 ==="
  ip addr flush dev enp0s8 || true
  ip addr add 192.168.56.10/24 dev enp0s8 || true
  ip link set enp0s8 up

  echo "=== Persisting master IP via netplan ==="
  cat > /etc/netplan/99-k8s.yaml << 'NETPLAN'
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.10/24
NETPLAN
  netplan apply || true

  echo "=== Verifying IP ==="
  ip addr show enp0s8

  echo "=== Initializing cluster ==="
  kubeadm init \
    --pod-network-cidr=10.244.0.0/16 \
    --apiserver-advertise-address=192.168.56.10

  echo "=== Setting up kubeconfig ==="
  export KUBECONFIG=/etc/kubernetes/admin.conf
  mkdir -p /home/vagrant/.kube
  cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
  chown vagrant:vagrant /home/vagrant/.kube/config
  echo 'export KUBECONFIG=$HOME/.kube/config' >> /home/vagrant/.bashrc

  echo "=== Mounting BPF filesystem ==="
  mount | grep -q /sys/fs/bpf || mount -t bpf bpffs /sys/fs/bpf
  echo 'bpffs /sys/fs/bpf bpf defaults 0 0' >> /etc/fstab

  echo "=== Installing Calico CNI ==="
  kubectl apply -f \
    https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

  echo "=== Waiting for Calico to be Ready ==="
  kubectl wait --for=condition=Ready pods -l k8s-app=calico-node \
    -n kube-system --timeout=180s

  echo "=== Waiting for master node to be Ready ==="
  kubectl wait --for=condition=Ready node/k8s-master --timeout=180s

  echo "=== Downloading Istio to /opt/istio ==="
  mkdir -p /opt/istio
  cd /opt/istio
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.21.0 sh -
  ISTIO_DIR=$(ls -d /opt/istio/istio-*/ | head -1)

  echo "=== Installing istioctl to system PATH ==="
  cp ${ISTIO_DIR}bin/istioctl /usr/local/bin/
  chmod +x /usr/local/bin/istioctl
  istioctl version --remote=false

  echo "=== Installing Gateway API CRDs ==="
  kubectl apply -f \
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

  echo "=== Installing Istio ambient profile ==="
  istioctl install --set profile=ambient -y

  echo "=== Waiting for istiod to be Ready ==="
  kubectl wait --for=condition=Ready pods -l app=istiod \
    -n istio-system --timeout=180s

  echo "=== Waiting for ztunnel to be Ready ==="
  kubectl rollout status daemonset/ztunnel \
    -n istio-system --timeout=180s

  echo "=== Enabling ambient mode on default namespace ==="
  kubectl label namespace default istio.io/dataplane-mode=ambient

  echo "=== Deploying waypoint proxy ==="
  istioctl waypoint apply --namespace default

  echo "=== Saving worker join command ==="
  kubeadm token create --print-join-command > /vagrant/join-command.sh
  chmod +x /vagrant/join-command.sh

  echo "=== Master setup complete ==="
  kubectl get nodes
  kubectl get pods -n istio-system
SHELL

WORKER_SCRIPT = <<~SHELL
  set -e

  echo "=== Assigning worker IP to enp0s8 ==="
  ip addr flush dev enp0s8 || true
  ip addr add 192.168.56.11/24 dev enp0s8 || true
  ip link set enp0s8 up

  echo "=== Persisting worker IP via netplan ==="
  cat > /etc/netplan/99-k8s.yaml << 'NETPLAN'
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: false
      addresses:
        - 192.168.56.11/24
NETPLAN
  netplan apply || true

  echo "=== Waiting for join command from master ==="
  for i in $(seq 1 30); do
    if [ -f /vagrant/join-command.sh ]; then
      echo "Join command found"
      break
    fi
    echo "Waiting... attempt $i/30"
    sleep 10
  done

  if [ ! -f /vagrant/join-command.sh ]; then
    echo "ERROR: join-command.sh not found after waiting"
    exit 1
  fi

  echo "=== Joining cluster ==="
  bash /vagrant/join-command.sh

  echo "=== Worker setup complete ==="
SHELL

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  config.vm.define "master" do |master|
    master.vm.hostname = "k8s-master"
    master.vm.network "private_network", ip: MASTER_IP
    master.vm.provider "virtualbox" do |vb|
      vb.name   = "k8s-master"
      vb.memory = "4096"
      vb.cpus   = 2
    end
    master.vm.provision "shell", inline: COMMON_SCRIPT
    master.vm.provision "shell", inline: MASTER_SCRIPT
  end

  config.vm.define "worker" do |worker|
    worker.vm.hostname = "k8s-worker"
    worker.vm.network "private_network", ip: WORKER_IP
    worker.vm.provider "virtualbox" do |vb|
      vb.name   = "k8s-worker"
      vb.memory = "4096"
      vb.cpus   = 2
    end
    worker.vm.provision "shell", inline: COMMON_SCRIPT
    worker.vm.provision "shell", inline: WORKER_SCRIPT
  end
end