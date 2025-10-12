---
layout: post
title: "low cost alternative to off-the-shelf k8s security dashboard"
date: 2025-10-10
categories: 
  - kubernetes
  - security
  - devsecops
---
security is a layered approach and in the kubernetes world, its has so many layers to deal with. as organizations increase their security focused initiatives especially from a security posture management standpoint, we see that there are lot of off-the-shell software that are used in this space. (e.g. wiz.io). although these do provide a very broad view of your entire stack beyond k8s and do bring in lot of value to the table to observe and reconcile across your tech stack and fix issues, we also see an opportunity to achieve some of this in a lot more simpler and robust manner for security operations

in this write-up, we will see how we can us `headlamp`(kubernetes sig project) as a off-the-shelf security dashboard integrating with `trivy` running in cluster to generate and visualize the vulnerability/compliance with ease in a dashboard

#### setup local machine
> **note:** assumes you have cloud provider CLI and config setup in your local

- install [headlamp](https://headlamp.dev/) on your desktop and [kubebeam/trivy-headlamp-plugin](https://github.com/kubebeam/trivy-headlamp-plugin) as as addon into `headlamp`


#### setup trivy operator
- install [trivy-operator deployment](https://artifacthub.io/packages/helm/trivy-operator/trivy-operator) on your kubernetes cluster
  > **note:** if you use corporate-proxy, ensure to set the values as below_
  ```yaml
  trivy:
    httpProxy: <your-http-proxy>
    httpsProxy: <your-https-proxy>
    noProxy: <no-proxy>
  ```

#### import kubeconfig
> **note:** this can be used for eks, aks & on-prem clusters_

- import `kubeconfig` for your k8s cluster
- use [serviceaccount](https://headlamp.dev/docs/latest/installation/#create-a-service-account-token) flow for simplicity purposes
  _**note:** oidc flow would be showcased in a separate post_

- from headlamp ui -> add cluster -> load from kubeconfig
![headlamp add cluster]({{ "/assets/image_1758878520002_0.png" | relative_url }})
![load from kubeconfig]({{ "/assets/image_1758878566648_0.png" | relative_url }})

- once added, you can see your cluster getting listed in `home`\
![cluster listed in home]({{ "/assets/image_1758878628349_0.png" | relative_url }})

#### verify trivy
```shell
# cluster vulnerabilities
❯ k get clustervulnerabilityreports.aquasecurity.github.io
NAME                                       REPOSITORY   TAG           SCANNER   AGE
clustersbomreport-6597787456-k8s-cluster   kubernetes   1.32.7-k3s1   Trivy     5d5h

# cluster compliance
❯ k get clustercompliancereports.aquasecurity.github.io
NAME                     AGE
k8s-cis-1.23             6d
k8s-nsa-1.0              6d
k8s-pss-baseline-0.1     6d
k8s-pss-restricted-0.1   6d

# RBAC assessments
❯ k get clusterrbacassessmentreports.aquasecurity.github.io -A
NAME                                                             SCANNER   AGE
clusterrole-547457d6d8                                           Trivy     6d
clusterrole-54ccb57cc4                                           Trivy     6d
clusterrole-54cdc9b678                                           Trivy     6d
clusterrole-5585c7b9ff                                           Trivy     6d
clusterrole-565cd5fdf                                            Trivy     6d
clusterrole-569d87574c                                           Trivy     6d
clusterrole-56bc9577c9                                           Trivy     6d
clusterrole-575b7f6784                                           Trivy     6d
clusterrole-57d745d4cc                                           Trivy     6d
clusterrole-584c484c4f                                           Trivy     6d
clusterrole-5857f84f59                                           Trivy     6d
clusterrole-586b8c778d                                           Trivy     6d
clusterrole-58bfc7788d                                           Trivy     6d
clusterrole-59dc5c9cb6                                           Trivy     6d
```

the specific settings around this can be found in the trivy operator [values.yaml](https://artifacthub.io/packages/helm/trivy-operator/trivy-operator?modal=values&path=operator.vulnerabilityScannerEnabled) (above one uses the defaults).

#### observe on headlamp dashboard
- check on headlamp ui -> <your-cluster> -> trivy
  - **compliance reports**
  ![compliance reports overview]({{ "/assets/image_1758879507809_0.png" | relative_url }})
  ![compliance report details]({{ "/assets/image_1758879532544_0.png" | relative_url }})
  ![compliance report analysis]({{ "/assets/image_1758879574806_0.png" | relative_url }})
  ![compliance report results]({{ "/assets/image_1758879598485_0.png" | relative_url }})
  - **vulnerability reports**
  ![vulnerability reports]({{ "/assets/image_1758879654311_0.png" | relative_url }})

#### value additions
- 0 cost k8s security posture management with addon based integration
- enables strong security posture management with a comprehensive view and can be expanded for full cluster view
- enables shift from reactive to proactive security operations of k8s clusters
- can be easily setup with just `kubeconfig` and respects `rbac` and works with `oidc`
- kubernetes sig team opensource project
- integrates seamlessly for managed cloud k8s clusters as well

#### operational maintenance
- need to update trivy addon regularly to latest versions
- need to modify resource allocations, scan settings as new workloads are added into the cluster
