---
layout: post
title: "my local k8s cluster - wsl2, kind, traefik, istio, gateway API and more..."
date: 2026-01-09
categories: 
  - platform-engineering
  - kubernetes
  - cloud-native
---
as a proponent of developer productivity and velocity, i have been involved with plethora of experience building initiatives for microservices deployments on kubernetes. in my experience to make this possible i have played with many kubernetes setups over time starting with [kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/) , [microk8s](https://canonical.com/microk8s) and [k3s](https://k3s.io/) however these fell short for me overtime

although no one size fits all and things can be worked out in an opinionated way with specific approaches and solutions, i have always been on the lookout for what intrigues me to complete this experience with some aspects that i hold close to me as below

*  ✅ real fast to setup and destroy - under 5 min
*  ✅ declarative deployment experience
*  ✅ works on local WSL2
*  ✅ provides dashboards and other batteries accessible via ingress

with [kind](https://kind.sigs.k8s.io/) , i was able to build a simple, declarative local-stack completely running inside WSL2 and it has been the best one to date i have ever built

## what's available

- [cloud-native postgres](https://cloudnative-pg.io/docs/1.28/)
- [prometheus & grafana](https://github.com/prometheus-community/helm-charts/tree/main)
- [traefik](https://doc.traefik.io/traefik/) with [gateway API](https://gateway-api.sigs.k8s.io/)
- [cert-manager](https://cert-manager.io/)
- [helm-controller](https://github.com/k3s-io/helm-controller)
- [elastic search & kibana](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/managing-deployments-using-helm-chart)
- [istio](https://istio.io/latest/docs/)

## screenshots

![image-20260109094120747]({{ "/assets/images/my-local-k8s-cluster/image-20260109094120747.png" | relative_url }})

![image-20260109094845115]({{ "/assets/images/my-local-k8s-cluster/image-20260109094845115.png" | relative_url }})

![image-20260109093952350]({{ "/assets/images/my-local-k8s-cluster/image-20260109093952350.png" | relative_url }})

![image-20260109094003427]({{ "/assets/images/my-local-k8s-cluster/image-20260109094003427.png" | relative_url }})

## show me the code 🧑‍💻

checkout my repo [here](https://github.com/raghav19/engineersdaybook/tree/main/code/devk8s-kind-wsl2)

## value

✅ allows self-service k8s clusters locally

✅ simple,fast, declarative experience

✅ great for developer productivity/velocity

✅ enables similar experience as a cloud provider locally with all dashboards tracking metrics/logs etc

✅ easy ingress with Gateway API

✅ amazing setup for learning/experimenting with cloud-native world

## tradeoffs

➖ need little beefy laptop with at least 32GB RAM
