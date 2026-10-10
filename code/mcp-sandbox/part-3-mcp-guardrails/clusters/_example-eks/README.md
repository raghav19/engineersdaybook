# Template: a second cluster (EKS, one region)

Not applied. Copy to `clusters/eks-<region>/` and edit:

```text
clusters/eks-eu-west-1/
├── cluster.env          PROVIDER=eks  REGION=eu-west-1  KUBE_CONTEXT=<arn or alias>
├── kustomization.yaml   resources: ../../profiles/phase-1
│                        components: values-wiring, and a secrets component for this cluster (ESO instead of secrets-sops)
│                        configMapGenerator (behavior: merge) from values.env
├── values.env           GATEWAY_PORT=443, hosts, replicas
└── patches/             Service annotations for the AWS Load Balancer Controller, PDB/HPA, IRSA
```

Also add `tasks/eks.yml` (`up`/`down`, or a pointer to the Terragrunt that owns the cluster).
`crds/`, `platform/`, `profiles/` and `services/` do not change.
