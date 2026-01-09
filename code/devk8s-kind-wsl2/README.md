# devk8s-kind-wsl2
a simple, declarative local kubernetes stack with kind & wsl2

## requirements
* [wsl2](https://learn.microsoft.com/en-us/windows/wsl/install) installed
* [docker](https://docs.docker.com/engine/install/) installed and running
* [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries) installed

## setup kind cluster

* create `kind.yaml`

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
- role: worker
  image: kindest/node:v1.33.7@sha256:d26ef333bdb2cbe9862a0f7c3803ecc7b4303d8cea8e814b481b09949d353040
- role: worker
  image: kindest/node:v1.33.7@sha256:d26ef333bdb2cbe9862a0f7c3803ecc7b4303d8cea8e814b481b09949d353040
EOF
```

* create `kind` cluster

```shell
kind create cluster --config kind.yaml
```

## install addons

#### crds

```shell
kubectl create -k crds

# wait for pods to be up and running
watch kubectl get pods -A
```

#### namespaces

```shell
kubectl apply -k namespaces
```

#### operators

```shell
kubectl apply -k addons/operators

# wait for pods to be up and running
watch kubectl get pods -A
```

#### services

```shell
kubectl apply -k addons/services
```

#### routes

```shell
kubectl apply -k addons/routes
```

#### check status

```shell
# wait for all pods to be up and running
watch kubectl get pods -A
```

## access dashboards
the dashboards can be accessed from your windows browser

#### k8s-dashboard
- create service account token for authentication

```shell
kubectl create token headlamp-admin -n kube-system --duration=24h
```

- access the dashboard
```http
# paste the token from previous step
http://localhost/
```

#### grafana

```http
http://localhost/grafana
```

#### prometheus

```http
http://localhost/prometheus
```

#### kibana

```http
http://localhost/kibana
```

## cleanup

```shell
kind delete cluster --name kind
```

## references
- [Accessing network applications with WSL | Microsoft Learn](https://learn.microsoft.com/en-us/windows/wsl/networking)
