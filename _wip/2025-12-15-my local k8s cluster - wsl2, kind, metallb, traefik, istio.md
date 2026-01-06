## my local k8s cluster - wsl2, kind, traefik, istio

## ## setup kind cluster

- create `kind.yaml`

  ```yaml
  cat << EOF > $HOME/kind.yaml
  ---
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  nodes:
  - role: control-plane
    image: kindest/node:v1.33.7@sha256:d26ef333bdb2cbe9862a0f7c3803ecc7b4303d8cea8e814b481b09949d353040
    extraPortMappings:
    - containerPort: 30080
      hostPort: 80
      protocol: TCP
      listenAddress: "127.0.0.1"
    - containerPort: 30443
      hostPort: 443
      protocol: TCP
      listenAddress: "127.0.0.1"
  - role: worker
    image: kindest/node:v1.33.7@sha256:d26ef333bdb2cbe9862a0f7c3803ecc7b4303d8cea8e814b481b09949d353040
  - role: worker
    image: kindest/node:v1.33.7@sha256:d26ef333bdb2cbe9862a0f7c3803ecc7b4303d8cea8e814b481b09949d353040
  EOF
  ```

- create `kind` cluster

  ```shell
  kind create cluster --config kind.yaml
  ```

## install addons

### helm-controller

```shell
wget https://github.com/k3s-io/helm-controller/releases/download/v0.16.17/deploy-cluster-scoped.yaml -O /tmp/helm-controller.yaml
kubectl apply --server-side -f /tmp/helm-controller.yaml


cat <<EOF > /tmp/patch.json
[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "HTTP_PROXY",
      "value": "http://proxy-us.intel.com:911"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "HTTPS_PROXY",
      "value": "http://proxy-us.intel.com:911"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "NO_PROXY",
      "value": "localhost,127.0.0.1,10.0.0.0/8,172.18.0.0/16,192.168.0.0/16,kind.svc.cluster.local"
    }
  }
]
EOF

kubectl patch deployment helm-controller -n helm-controller --type='json' --patch-file /tmp/patch.json
```

### other addons

#### install crds

```shell
kubectl apply --server-side -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.crds.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/external-secrets/external-secrets/refs/tags/v1.1.1/deploy/crds/bundle.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.28/releases/cnpg-1.28.0.yaml
kubectl apply --server-side -f https://download.elastic.co/downloads/eck/3.2.0/crds.yaml
```

#### create namespaces

```yaml
cat << EOF | kubectl apply -f -
---
# NAMESPACES
apiVersion: v1
kind: Namespace
metadata:
  name: app
---
apiVersion: v1
kind: Namespace
metadata:
  name: observability
EOF
```

#### deploy addons

```yaml
cat << EOF | kubectl apply -f -
---
# ELASTIC-OPERATOR
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: eck-operator
  namespace: kube-system
spec:
  chart: eck-operator
  targetNamespace: observability
  createNamespace: true
  repo: https://helm.elastic.co
  version: 3.2.0
  valuesContent: |
    installCRDs: false
    telemetry:
      disabled: true
---
# TRAEFIK
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: traefik
  namespace: kube-system
spec:
  chart: traefik
  targetNamespace: traefik
  createNamespace: true
  repo: https://traefik.github.io/charts
  version: 37.4.0
  valuesContent: |
    logs:
      access:
        enabled: true
    providers:
      kubernetesIngress:
        enabled: false
      kubernetesGateway:
        enabled: true
    gateway:
      namespace: traefik
      name: traefik
      listeners:
        web:
          port: 80
          namespacePolicy:
            from: All
    ports:
      web:
        # match gateway listener
        port: 80
        nodePort: 30080
        exposedPort: 80
        protocol: TCP
---
# CERT-MANAGER
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: cert-manager
  namespace: kube-system
spec:
  chart: cert-manager
  targetNamespace: cert-manager
  createNamespace: true
  repo: https://charts.jetstack.io
  version: 1.19.2
  set:
    crds.enabled: "false"
    http_proxy: "${HTTP_PROXY}"
    https_proxy: "${HTTPS_PROXY}"
    no_proxy: "${NO_PROXY}"
---
# EXTERNAL-SECRETS
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: external-secrets
  namespace: kube-system
spec:
  chart: external-secrets
  targetNamespace: external-secrets
  createNamespace: true
  repo: https://charts.external-secrets.io
  version: 1.1.1
  set:
    installCRDs: "false"
---
# POSTGRES
apiVersion: v1
kind: Secret
metadata:
  name: postgres-auth
  namespace: cnpg-system
type: kubernetes.io/basic-auth
stringData:
  username: postgres
  password: postgrespassword
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-cluster
  namespace: cnpg-system
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:15.4
  enableSuperuserAccess: true
  superuserSecret:
    name: postgres-auth
  storage:
    size: 2Gi
    storageClass: standard
  bootstrap:
    initdb:
      database: app
      owner: postgres
      secret:
        name: postgres-auth
  postgresql:
    parameters:
      log_connections: "on"
      log_disconnections: "on"
    pg_hba:
      - host all all all md5
---
# PROMETHEUS-GRAFANA
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: prometheus
  namespace: kube-system
spec:
  chart: kube-prometheus-stack
  targetNamespace: observability
  createNamespace: true
  repo: https://prometheus-community.github.io/helm-charts
  version: 80.4.1
  valuesContent: |
    kubeStateMetrics:
      enabled: true
    kube-state-metrics:
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
      limits:
        cpu: 100m
        memory: 256Mi
    grafana:
      enabled: true
      persistence:
        enabled: true
        size: 500Mi
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 100m
          memory: 256Mi
      adminPassword: admin
      ingress:
        enabled: false
      grafana.ini:
        auth:
          anonymous:
            enabled: true
            org_role: Viewer
        server:
          domain: localhost
          root_url: http://localhost/grafana
          serve_from_sub_path: true
    alertmanager:
      enabled: false
    prometheus-node-exporter:
      containerSecurityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        readOnlyRootFilesystem: true
    prometheus:
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 1000
        readOnlyRootFilesystem: true
      ingress:
        enabled: false
      prometheusSpec:
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 250m
            memory: 512Mi
        routePrefix: /prometheus
        externalUrl: http://localhost/prometheus
        storageSpec:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 2Gi
              storageClassName: standard
        retention: 3d
        retentionSize: 1.5GiB
    prometheusOperator:
      admissionWebhooks:
        certManager:
          enabled: false
        patch:
          enabled: true
          podAnnotations:
            sidecar.istio.io/inject: "false"
        create:
          enabled: true
          podAnnotations:
            sidecar.istio.io/inject: "false"
---
# ELASTICSEARCH-KIBANA
apiVersion: v1
kind: Secret
metadata:
  name: elasticsearch-es-elastic-user
  namespace: observability
stringData:
  elastic: elasticPassword
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: es-ilm-policy
  namespace: observability
data:
  ilm-policy.json: |
    {
      "policy": "logs-policy",
      "phases": {
        "hot": {
          "min_age": "0ms",
          "actions": {
            "rollover": {
              "max_primary_size": "500mb",
              "max_age": "1d"
            }
          }
        },
        "delete": {
          "min_age": "3d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
---
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
  namespace: observability
spec:
  version: 9.2.3
  nodeSets:
    - name: default
      count: 1
      config:
        node.store.allow_mmap: false
      podTemplate:
        spec:
          containers:
          - name: elasticsearch
            resources:
              requests:
                memory: "512Mi"
                cpu: "250m"
              limits:
                memory: "1Gi"
                cpu: "500m"
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 2Gi
            storageClassName: standard
  http:
    tls:
      selfSignedCertificate:
        disabled: true  
---
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: kibana
  namespace: observability
spec:
  version: 9.2.3
  count: 1
  podTemplate:
    spec:
      containers:
      - name: kibana
        env:
        - name: NODE_OPTIONS
          value: "--max-old-space-size=1024" 
        resources:
          requests:
            memory: 1Gi
            cpu: 500m
          limits:
            memory: 1.5Gi
            cpu: 1000m
  config:
    telemetry.optIn: false
    telemetry.enabled: false
    server.basePath: "/kibana"
    server.xsrf.allowlist: ["/kibana"]
    server.rewriteBasePath: true
    xpack.fleet.enabled: false
  elasticsearchRef:
    name: elasticsearch
  http:
    tls:
      selfSignedCertificate:
        disabled: true
EOF
```

### ### setup ingress rules

```yaml
cat << EOF | kubectl apply -f -
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: observability
spec:
  parentRefs:
    - name: traefik
      namespace: traefik
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /grafana
      backendRefs:
        - name: prometheus-grafana
          port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: prometheus
  namespace: observability
spec:
  parentRefs:
      - name: traefik
        namespace: traefik
  rules:
    - backendRefs:
        - name: prometheus-kube-prometheus-prometheus
          port: 9090
      matches:
        - path:
            type: PathPrefix
            value: /prometheus
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kibana
  namespace: observability
spec:
  parentRefs:
    - name: traefik
      namespace: traefik
  rules:
    - backendRefs:
        - name: kibana-kb-http
          port: 5601
      matches:
        - path:
            value: /kibana
EOF
```

[Accessing network applications with WSL | Microsoft Learn](https://learn.microsoft.com/en-us/windows/wsl/networking)

