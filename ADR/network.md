## istio(service mesh)
 - k8s gateway api controller
   - istio gateway : implementation of k8s gateway api
 - mtls support
 - ambient mesh (replace resource demanding envoy proxy)
   - ztunnel (L4) per node
   - waypoint (l7) per service
 - deployment strategy support (canary release)

## k8s gateway
 - http route configuration
 - 