#!/bin/bash
set -e

export KUBECONFIG=/etc/kubernetes/admin.conf

echo "=== Waiting for all nodes to be Ready ==="
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "=== Downloading Istio to /opt/istio ==="
mkdir -p /opt/istio
cd /opt/istio
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.29.1 sh -
ISTIO_DIR=$(ls -d /opt/istio/istio-*/ | head -1)

echo "=== Installing istioctl to system PATH ==="
cp ${ISTIO_DIR}bin/istioctl /usr/local/bin/
chmod +x /usr/local/bin/istioctl
istioctl version --remote=false

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

echo "=== Deploying Istio Gateway ==="
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

echo "=== Waiting for Gateway to be Ready ==="
kubectl wait --for=condition=Programmed gateway/istio-gateway \
  -n default --timeout=180s || true

echo "=== Installing Harbor registry ==="
helm repo add harbor https://helm.goharbor.io
helm repo update

echo "=== Creating harbor namespace ==="
kubectl create namespace harbor || true

echo "=== Installing Harbor with ClusterIP ==="
helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=clusterIP \
  --set expose.tls.enabled=false \
  --set expose.clusterIP.name=harbor \
  --set externalURL=http://192.168.56.10/harbor \
  --set harborAdminPassword=Harbor12345 \
  --set persistence.enabled=false

echo "=== Waiting for Harbor to be Ready ==="
kubectl wait --for=condition=Ready pods -l component=core \
  -n harbor --timeout=300s || true

echo "=== Creating HTTPRoute for Harbor via Gateway at /harbor path ==="
kubectl apply -f - <<'HTTPROUTE'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: harbor-route
  namespace: harbor
spec:
  parentRefs:
  - name: istio-gateway
    namespace: default
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /harbor
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /
    backendRefs:
    - name: harbor
      port: 80
HTTPROUTE

echo "=== Harbor Access Info ==="
echo "Harbor UI: http://192.168.56.10/harbor"
echo "Username: admin"
echo "Password: Harbor12345"

echo "=== Installation complete ==="
kubectl get nodes
kubectl get pods -n istio-system
kubectl get pods -n harbor
