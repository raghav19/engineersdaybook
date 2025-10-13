---
layout: page
title: about me
permalink: /about.html
---

## raghavender (raghav) nagarajan

**email:** raghavendern@hotmail.com  
**location:** germany  
**github:** [github.com/raghav19](https://github.com/raghav19)  
**linkedin:** [linkedin.com/in/raghavender-nagarajan](https://www.linkedin.com/in/raghavender-nagarajan-683743141)

### summary

infrastructure and devops engineer with 12 years hands-on experience in multi-cloud solution architecture, infrastructure and devsecops. adept in designing, deploying, managing scalable multi-cloud, cloud-native hybrid infrastructures, cicd pipelines, ephemeral environments across aws/azure and on-prem.

### skills

**cloud platforms & virtualization:**
- **aws:** eks, ecr, s3, lambda, cloudfront, route53, rds, msk, apigw, iam, opensearch, cloudwatch, bedrock
- **azure:** aks, acr, vault, azure vms (confidential compute), openai foundry
- **on-prem:** rancher(k3s), openstack, vmware
- **others:** docker, kubernetes

**infrastructure as code:** terraform, helm, kustomize, ansible, python, groovy, bash

**cicd:** fluxcd, github actions, jenkins, gitlab, teamcity

**service mesh:** istio (traffic management/security)

**policy as code:** kyverno

**observability:** prometheus, grafana, kiali, fluentbit, elasticsearch

**qa automation:** postman, readyapi, robot framework

### current role

**intel deutschland gmbh** — infrastructure & devops engineer  
*may 2023 - present*

- led design and implementation of 150k+ loc security saas platform deployment on aws/azure with a 10+ member devsecops team, scaling to 1m+ requests/day for intel trust authority using terraform/terraform modules, ansible, python
- led design and implementation of 10k+ loc deployment with 5-member team, shipped as cnab, supporting 1m+ requests/day for intel trust authority on enterprise on-prem using kustomize, porter(cnab), python, flux cd
- co-designed and implemented full cicd with cost savings of 40% ($200k→$120k) with advanced traffic management using istio for ephemeral sandbox environments reducing developer toil without replicating full deployments per namespace in kubernetes across actively running 35 microservices/50 developers/8hours/5days/52week span
- designed and implemented cni networking with calico for eks & aks on aws & azure clusters as part of hybrid infrastructure setup
- implemented 0-downtime node maintenance through automated security patching of amis(eks) and maintenance windows(aks), increasing operational efficiency by 90% across 15 clusters on aws and azure (4 hours → 25min)
- enabled on-demand confidential compute infrastructure provisioning on azure(aks, vms) via self-service
- developed environments-as-a-service (eaas) abstraction with kubernetes & istio gateway, enabling isolated, parallel app deployment/testing for 60+ engineers, 30+ environments, 15 clusters (aws/azure), enabled via self-service deployment workflows orchestrated with terraform, ansible & python
- implemented devcontainers for infra code & cicd to standardize self-contained local development and cicd images
- slashed cloud costs 30% ($250k→$175k) via finops strategies like spot instances, log retention, service consolidation, feature flags, weekend pod scale-down, vpa all via iac
- slashed container startup times by an average of 80% with lazy-pulling(soci-snapshotter) across 30+ services
- improved k8s cluster/app reliability & security posture cluster autoscaler, pod autoscalers, disruption budgets, priority classes, anti-affinity, topology spread constraints, maintenance windows, admission control policies (pod security standards & tolerations)
- developed a poc leveraging copilot chatmode, prompts and instructions to generate ai-driven prds, epics, and user stories, significantly boosting productivity and streamlining sdlc
- enabled shift-left security testing via gpt-4.1 generated summaries of trivy reports with azure openai foundry
- developed agentic ai poc with aws bedrock to showcase eks app lifecycle as a generative ai experience
- co-designed enterprise multi-tenant infra on kubernetes with namespace/workload isolation, network policies, admission control, rbac, istio auth

### experience

**intel india pvt ltd, bangalore** — sdet / devops engineer  
*apr 2018 - apr 2023*

- reduced developer toil by slashing local env setup time by 95% (from 3 hours to 10 minutes) using an all-in-one kubernetes(k3s)
- automated intel security libraries deployment on-prem kubernetes (vmware, bare-metal) using ansible and jenkins
- openstack nova and ironic for compute infrastructure automation
- developed test automation suites to enable automated testing with readyapi, postman collections
- developed helm chart libraries for deployment of intel security libraries - data center(open-source) project

**trianz holdings pvt ltd, bangalore** — senior software engineer  
*aug 2014 - mar 2018*

- developed ui test automation suites with selenium webdriver
- developed test suites for data integrity checks on apache kafka/spark big data platform (contract: netapp india)

### education

bachelor of engineering (instrumentation), india
