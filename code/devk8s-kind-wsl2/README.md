# devk8s-kind-wsl2
a simple, declarative local kubernetes stack with kind & wsl2

## requirements
* [wsl2](https://learn.microsoft.com/en-us/windows/wsl/install) installed
* [docker](https://docs.docker.com/engine/install/) installed and running
* [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries) installed
* [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
* this repo cloned. run every command in the folder `code/devk8s-kind-wsl2`
* port 80 on the host is free. the kind config binds it to `127.0.0.1`
* enough memory for the WSL2 VM. Elasticsearch and Kibana alone request 1.5 GiB and have limits of 2.5 GiB (`addons/services/logging.yaml`)

## setup kind cluster

* create `kind.yaml`

```shell
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
kind create cluster --config "$HOME/kind.yaml"
```

## install addons

#### crds

this step installs the Gateway API CRDs, the k3s helm-controller (it runs the `HelmChart` objects of the next steps), the CloudNativePG operator and the cert-manager and ECK CRDs

```shell
# run this step once. a second run fails with AlreadyExists
# to start again, delete the cluster and create it again
kubectl create -k crds

# wait until all pods are Running or Completed. press Ctrl+C to leave watch
watch kubectl get pods -A
```

#### namespaces

```shell
kubectl apply -k namespaces
```

#### operators

this step installs cert-manager and the ECK operator

```shell
kubectl apply -k addons/operators

# wait until all pods are Running or Completed. press Ctrl+C to leave watch
watch kubectl get pods -A
```

#### services

this step installs Traefik (the gateway), metrics-server, Prometheus and Grafana, Elasticsearch and Kibana, a PostgreSQL cluster (CloudNativePG) and Headlamp

```shell
kubectl apply -k addons/services
```

#### routes

this step adds one `HTTPRoute` for each dashboard: Headlamp, Grafana, Prometheus and Kibana

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

- the user is `admin`. the password is `adminPassword` in `addons/services/metrics.yaml`

#### prometheus

```http
http://localhost/prometheus
```

#### kibana

```http
http://localhost/kibana
```

- the user is `elastic`. the password is in the secret `elasticsearch-es-elastic-user` in `addons/services/logging.yaml`

## cleanup

```shell
kind delete cluster --name kind
```

## references
- [Accessing network applications with WSL | Microsoft Learn](https://learn.microsoft.com/en-us/windows/wsl/networking)
