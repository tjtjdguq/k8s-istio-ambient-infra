#!/bin/bash
set -e

export KUBECONFIG=/etc/kubernetes/admin.conf

echo "=== Waiting for all nodes to be Ready ==="
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "=== Downloading Istio to /opt/istio ==="
if [ ! -d /opt/istio/istio-1.29.1 ]; then
  mkdir -p /opt/istio
  cd /opt/istio
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.29.1 sh -
fi
ISTIO_DIR=/opt/istio/istio-1.29.1/

echo "=== Installing istioctl to system PATH ==="
cp ${ISTIO_DIR}bin/istioctl /usr/local/bin/
chmod +x /usr/local/bin/istioctl
istioctl version --remote=false

echo "=== Installing MetalLB ==="
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

echo "=== Waiting for MetalLB to be Ready ==="
kubectl wait --for=condition=Ready pods -l app=metallb -n metallb-system --timeout=180s

echo "=== Configuring MetalLB IP pool ==="
kubectl apply -f - <<'METALLB'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.56.200-192.168.56.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
METALLB

echo "=== Installing Gateway API CRDs ==="
kubectl apply -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

echo "=== Installing Helm ==="
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "=== Installing Istio ambient profile ==="
istioctl install --set profile=ambient -y

echo "=== Waiting for istiod to be Ready ==="
kubectl wait --for=condition=Ready pods -l app=istiod \
  -n istio-system --timeout=300s

echo "=== Waiting for ztunnel to be Ready ==="
kubectl rollout status daemonset/ztunnel \
  -n istio-system --timeout=300s

echo "=== Enabling ambient mode on default namespace ==="
kubectl label namespace default istio.io/dataplane-mode=ambient --overwrite

echo "=== Deploying waypoint proxy ==="
istioctl waypoint apply --namespace default

echo "=== Deploying Istio Gateway (service traffic) ==="
kubectl apply -f - <<'GATEWAY'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-gateway
  namespace: default
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
GATEWAY

echo "=== Waiting for istio-gateway to be Ready ==="
kubectl wait --for=condition=Programmed gateway/istio-gateway \
  -n default --timeout=180s || true

echo "=== Deploying Admin Gateway (operator traffic) ==="
kubectl apply -f - <<'ADMIN_GATEWAY'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: admin-gateway
  namespace: default
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
ADMIN_GATEWAY

echo "=== Waiting for admin-gateway to be Ready ==="
kubectl wait --for=condition=Programmed gateway/admin-gateway \
  -n default --timeout=180s || true

echo "=== Getting admin-gateway external IP ==="
ADMIN_GW_IP=""
for i in $(seq 1 30); do
  ADMIN_GW_IP=$(kubectl get gateway admin-gateway -n default \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
  if [ -n "$ADMIN_GW_IP" ]; then
    echo "Admin Gateway IP: $ADMIN_GW_IP"
    break
  fi
  echo "Waiting for admin-gateway IP... attempt $i/30"
  sleep 5
done

echo "=== Installing Harbor registry ==="
helm repo add harbor https://helm.goharbor.io
helm repo update

echo "=== Creating harbor namespace ==="
kubectl create namespace harbor || true

echo "=== Setting up Harbor persistent storage under shared folder ==="
mkdir -p /vagrant/harbor/{registry,database,redis,jobservice,trivy}
chmod -R 777 /vagrant/harbor

kubectl apply -f - <<'HARBOR_STORAGE'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: harbor-local
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-registry-pv
spec:
  capacity:
    storage: 5Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: harbor-local
  hostPath:
    path: /vagrant/harbor/registry
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-database-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: harbor-local
  hostPath:
    path: /vagrant/harbor/database
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-redis-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: harbor-local
  hostPath:
    path: /vagrant/harbor/redis
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-jobservice-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: harbor-local
  hostPath:
    path: /vagrant/harbor/jobservice
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-trivy-pv
spec:
  capacity:
    storage: 5Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: harbor-local
  hostPath:
    path: /vagrant/harbor/trivy
    type: DirectoryOrCreate
HARBOR_STORAGE

echo "=== Installing Harbor with ClusterIP ==="
helm upgrade --install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=clusterIP \
  --set expose.tls.enabled=false \
  --set expose.clusterIP.name=harbor \
  --set externalURL=http://${ADMIN_GW_IP} \
  --set harborAdminPassword=Harbor12345 \
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.registry.storageClass=harbor-local \
  --set persistence.persistentVolumeClaim.registry.size=5Gi \
  --set persistence.persistentVolumeClaim.database.storageClass=harbor-local \
  --set persistence.persistentVolumeClaim.database.size=1Gi \
  --set persistence.persistentVolumeClaim.redis.storageClass=harbor-local \
  --set persistence.persistentVolumeClaim.redis.size=1Gi \
  --set "persistence.persistentVolumeClaim.jobservice.jobLog.storageClass=harbor-local" \
  --set "persistence.persistentVolumeClaim.jobservice.jobLog.size=1Gi" \
  --set persistence.persistentVolumeClaim.trivy.storageClass=harbor-local \
  --set persistence.persistentVolumeClaim.trivy.size=5Gi

echo "=== Waiting for Harbor to be Ready ==="
kubectl wait --for=condition=Ready pods -l component=core \
  -n harbor --timeout=300s || true

echo "=== Creating HTTPRoute for Harbor via admin-gateway ==="
kubectl apply -f - <<'HTTPROUTE'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: harbor-route
  namespace: harbor
spec:
  parentRefs:
  - name: admin-gateway
    namespace: default
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: harbor
      port: 80
HTTPROUTE

echo "=== Harbor Access Info ==="
echo "Harbor UI: http://${ADMIN_GW_IP}"
echo "Username: admin"
echo "Password: Harbor12345"

echo "=== Installing GitHub Actions Runner Controller ==="
if [ -z "${GITHUB_TOKEN}" ]; then
  echo "SKIP: GITHUB_TOKEN not set. To install ARC, re-run with:"
  echo "  GITHUB_TOKEN=<your-pat> sudo -E bash /vagrant/install-apps.sh"
else
  helm upgrade --install arc \
    --namespace arc-systems \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

  echo "=== Waiting for ARC controller to be Ready ==="
  kubectl wait --for=condition=Available \
    deployment/arc-gha-runner-scale-set-controller \
    -n arc-systems --timeout=180s

  helm upgrade --install arc-runner-set \
    --namespace arc-runners \
    --create-namespace \
    --set githubConfigUrl="https://github.com/tjtjdguq/project-store" \
    --set githubConfigSecret.github_token="${GITHUB_TOKEN}" \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set

  echo "=== Waiting for ARC runner set to be Ready ==="
  kubectl wait --for=condition=Available \
    deployment/arc-runner-set-gha-runner-scale-set \
    -n arc-runners --timeout=180s || true

  echo "=== ARC Runner Info ==="
  kubectl get pods -n arc-systems
  kubectl get pods -n arc-runners
fi

echo "=== Installation complete ==="
kubectl get nodes
kubectl get pods -n istio-system
kubectl get pods -n harbor
