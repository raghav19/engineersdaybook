---
layout: post
title: "Low cost alternative to off-the-shelf k8s security dashboard"
date: 2025-10-10
categories: 
  - kubernetes
  - security
  - devsecops
---
Security is a layered approach and in the Kubernetes world, its has so many layers to deal with. As organizations increase their security focused initiatives especially from a security posture management standpoint, we see that there are lot of off-the-shell software that are used in this space. (e.g. wiz.io). Although these do provide a very broad view of your entire stack beyond K8s and do bring in lot of value to the table to observe and reconcile across your tech stack and fix issues, we also see an opportunity to achieve some of this in a lot more simpler and robust manner for security operations
- In this write-up, we will see how we can us `headlamp` as a off-the-shelf security dashboard integrating with `trivy` running in cluster to generate and visualize the vulnerability/compliance with ease in a dashboard

#### Setup Local machine
- Install Chocolatey & Tools
  - Install [Chocolatey Software](https://chocolatey.org/install) on Windows
  - Install `awscli`/`azure-cli`
    ```shell
    # requires elevated powershell 
    choco install awscli azure-cli
    ```
- Setup local credentials for [AWS](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html) & [Azure](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli?view=azure-cli-latest)

- Install Headlamp and plugins
  - Install [Headlamp](https://headlamp.dev/) on your local machine
  - Install [kubebeam/trivy-headlamp-plugin](https://github.com/kubebeam/trivy-headlamp-plugin), can be done via headlamp UI (Home -> Plugin Catalog)

#### Setup Trivy Operator
- Install [trivy-operator deployment](https://artifacthub.io/packages/helm/trivy-operator/trivy-operator)
  
  _**Note:** If you use corporate-proxy, ensure to set the values as below_
  ```yaml
  trivy:
    httpProxy: <your-http-proxy>
    httpsProxy: <your-https-proxy>
    noProxy: <no-proxy>
  ```

#### Import Kubeconfig
_**Note:** This can be used for EKS, AKS & On-prem clusters_

- Import `kubeconfig` for your K8s cluster
- Use [serviceaccount](https://headlamp.dev/docs/latest/installation/#create-a-service-account-token) flow for simplicity purposes
  
  _**Note:** OIDC flow would be showcased in a separate post_
  - From Headlamp UI -> Add Cluster -> Load From Kubeconfig
    - ![Headlamp Add Cluster]({{ "/assets/image_1758878520002_0.png" | relative_url }})
    - ![Load From Kubeconfig]({{ "/assets/image_1758878566648_0.png" | relative_url }})
- Once added, you can see your cluster getting listed in `HOME`
  - ![Cluster Listed in Home]({{ "/assets/image_1758878628349_0.png" | relative_url }})

#### Verify Trivy
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

The specific settings around this can be found in the trivy operator [values.yaml](https://artifacthub.io/packages/helm/trivy-operator/trivy-operator?modal=values&path=operator.vulnerabilityScannerEnabled) (above one uses the defaults).

#### Observe on Headlamp Dashboard
- Check on Headlamp UI -> <your-cluster> -> Trivy
  - **Compliance Reports**
    - ![Compliance Reports Overview]({{ "/assets/image_1758879507809_0.png" | relative_url }})
    - ![Compliance Report Details]({{ "/assets/image_1758879532544_0.png" | relative_url }})
    - ![Compliance Report Analysis]({{ "/assets/image_1758879574806_0.png" | relative_url }})
    - ![Compliance Report Results]({{ "/assets/image_1758879598485_0.png" | relative_url }})
  - **Vulnerability Reports**
    - ![Vulnerability Reports]({{ "/assets/image_1758879654311_0.png" | relative_url }})

#### Value Additions
- 0 cost K8s Security Posture management with addon based integration
- Enables strong security posture management with a comprehensive view and can be expanded for full Cluster view
- Enables shift from reactive to proactive security operations of k8s clusters
- Can be easily setup with just `kubeconfig` and respects `RBAC` and works with `OIDC`
- Kubernetes`SIG` team opensource project
- Integrates seamlessly for Managed Cloud K8s clusters as well

#### Operational Maintenance
- Need to update trivy addon regularly to latest versions
- Need to modify resource allocations, scan settings as new workloads are added into the cluster
