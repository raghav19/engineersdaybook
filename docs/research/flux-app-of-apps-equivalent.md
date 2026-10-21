# The Flux CD equivalent of the Argo CD app-of-apps pattern

Question: What is the Flux CD equivalent of the Argo CD "app of apps" pattern, what does a concrete example look like, and where does `code/mcp-sandbox/part-3-mcp-guardrails` match or differ from the shape the Flux docs describe?

Source: the Argo CD "Cluster Bootstrapping" page, the Flux `Kustomization` API page, the Flux "Ways of structuring your repositories" guide, the Flux Operator `ResourceSet`, `ResourceSetInputProvider` and `FluxInstance` pages, and the repos `fluxcd/flux2-kustomize-helm-example`, `fluxcd/flux2-multi-tenancy` and `controlplaneio-fluxcd/d1-fleet`. All fetched on 2026-10-21. Repo claims are at branch commit `aafad5d`. The generic example in section 1 uses the names `addons` and `policies` and is not the part 3 layout.

Status: done. The example YAML passed `yq` and `flux-schema validate`. I did not run it on a cluster.

Evidence tags: **[docs]** project documentation. **[repo-example]** a file in an upstream example repo. **[repo]** a file in this repo. **[inference]** my own conclusion.

## Comparison

| Argo CD term | Flux term | Part 3 |
|---|---|---|
| Parent `Application` that holds a folder of child `Application` objects | Root `Kustomization` that applies a path holding more `Kustomization` objects | `flux-system` (made by the `FluxInstance`) applies `sync/local-kind`, which holds `apps.yaml` |
| Child `Application` (an "app") | Group `Kustomization` over a path of units | `secrets` (3 units), `mesh` (3 units), `gateway` (7 units) |
| `Application` = repo + path + revision + destination + syncPolicy | Source object (`GitRepository`, `OCIRepository`, `HelmRepository`) plus `Kustomization` or `HelmRelease` | One `OCIRepository` plus one `Kustomization` per unit |
| `ApplicationSet` (recommended by Argo) | `ResourceSet` plus `ResourceSetInputProvider` (Flux Operator) | Not used |
| Sync waves, or health assessment of `Application` | `dependsOn` plus `wait: true` | Unit-level `dependsOn` only, also across groups. No group-level `dependsOn` |
| Finalizer `resources-finalizer.argocd.argoproj.io` (opt-in cascade) | `prune` and `deletionPolicy` (cascade by default) | `prune: true`, `deletionPolicy: Orphan` on the groups |
| `argocd app create apps` (bootstrap the parent) | `FluxInstance` `spec.sync` or `flux bootstrap --path` | `FluxInstance` `spec.sync.path` |

## Verdict

1. The direct equivalent is a root `Kustomization` that applies a path full of `Kustomization` objects. Flux has no `Application` kind, so each "app" is a `Kustomization`, with a source object next to it when the source is not the cluster Git repository. [inference]
2. `ResourceSet` is the closest match to `ApplicationSet`, but it is not one-to-one. One `ResourceSet` generates many Flux objects from inputs, and it has one inventory and one `Ready` condition. It needs the Flux Operator. [docs]
3. The Flux docs recommend the layout `clusters/<name>`, `infrastructure/`, `apps/`, with a `dependsOn` chain such as `infra-controllers` then `infra-configs` then `apps`. The guide shows the layout. The `dependsOn` chain lives in the example repo. [docs] [repo-example]
4. Deletion differs. In Argo the cascade is opt-in through a finalizer. In Flux the default `MirrorPrune` deletes the applied objects when `prune` is `true`. Deleting a parent therefore deletes the child `Kustomization` objects, and they delete their workloads in turn. [docs] [inference]
5. Suspending a parent `Kustomization` does not suspend its children. The children are separate objects that keep reconciling. [inference]
6. Part 3 uses shape 1 with three changes from the docs: a generated stack file, an OCI artifact per unit, and group `Kustomization` objects that reuse the `GitRepository` `flux-system` with no per-group source. [repo]

## 1. Root Kustomization over group and leaf Kustomizations

Argo side. The parent `Application` points at a folder of child `Application` manifests. The Argo CD page calls it "App Of Apps Pattern (Alternative)" and says "Our recommendation is to look at ApplicationSets". It also warns that "Only admins should have push access to the parent Application's source repository". [docs] https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/

Flux side. A `Kustomization` applies "plain Kubernetes manifests" from `.spec.path`, and a `Kustomization` is itself a Kubernetes manifest. So a path of `Kustomization` objects works. If a path has no `kustomization.yaml`, Flux generates one for all manifests in the tree. The docs still recommend storing your own. [docs] https://fluxcd.io/flux/components/kustomize/kustomizations/

Two upstream repos show the shape. In `flux2-multi-tenancy`, `clusters/<name>/policies.yaml` and `tenants.yaml` are `Kustomization` objects, and `tenants` has `dependsOn: policies`. [repo-example] https://github.com/fluxcd/flux2-multi-tenancy (README, "Reconciliation hierarchy"). In `d1-fleet`, the `FluxInstance` syncs `clusters/staging`. That folder holds `infra-tenant.yaml`, a `Kustomization` with `path: ./tenants/infra`. That path holds a `GitRepository` and `Kustomization` pair per component. This is root, group, leaf with a source per leaf. [repo-example] https://github.com/controlplaneio-fluxcd/d1-fleet (`clusters/staging/flux-system/flux-instance.yaml`, `clusters/staging/infra-tenant.yaml`, `tenants/infra/components/source.yaml`)

### Example

The root is the `Kustomization` that `flux bootstrap --path=clusters/demo` or a `FluxInstance` with `sync.path: clusters/demo` creates. Layout:

```text
clusters/demo/groups.yaml          # root path: the two group Kustomizations
groups/addons/cert-manager.yaml    # leaf: OCIRepository + Kustomization
groups/addons/external-secrets.yaml
groups/policies/rate-limit.yaml
```

`clusters/demo/groups.yaml`. Group `policies` waits for group `addons`.

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: {name: addons, namespace: flux-system}
spec:
  interval: 10m
  retryInterval: 1m
  timeout: 10m # longer than the longest dependsOn chain of the leaves
  prune: true
  wait: true
  path: ./groups/addons
  sourceRef: {kind: GitRepository, name: flux-system}
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: {name: policies, namespace: flux-system}
spec:
  dependsOn:
    - name: addons
  interval: 10m
  retryInterval: 1m
  timeout: 5m
  prune: true
  wait: true
  path: ./groups/policies
  sourceRef: {kind: GitRepository, name: flux-system}
```

`groups/addons/cert-manager.yaml`. A leaf is a source and a `Kustomization`.

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: {name: cert-manager, namespace: flux-system}
spec:
  interval: 5m
  url: oci://ghcr.io/example-org/demo/cert-manager
  ref: {tag: 1.0.0}
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: {name: cert-manager, namespace: flux-system}
spec:
  interval: 10m
  retryInterval: 1m
  timeout: 5m
  prune: true
  wait: true
  path: ./
  sourceRef: {kind: OCIRepository, name: cert-manager}
```

`groups/addons/external-secrets.yaml` is the same with the name changed and one more field in the `Kustomization` spec, a leaf-level `dependsOn`:

```yaml
  dependsOn:
    - name: cert-manager
```

`groups/policies/rate-limit.yaml` is the same shape again with no `dependsOn`. `dependsOn` works between groups and between leaves, because all of them are `Kustomization` objects in `flux-system`. [docs] The `dependsOn` rule: a `Kustomization` "is only applied after the referred Kustomizations are ready". If `wait` is `true`, it waits for the dependencies' health checks. [docs]

Check I ran: all five files parse with `yq`. `flux-schema validate` reported 8 resources valid.

## 2. ResourceSet as the ApplicationSet equivalent

The Flux Operator docs define `ResourceSet` as "a declarative API for generating a group of Kubernetes objects based on a matrix of input values and a set of templated resources". [docs] https://fluxoperator.dev/docs/crd/resourceset/

What it is not. An Argo `ApplicationSet` generates `Application` objects, and each one has its own status and sync. A `ResourceSet` generates any Kubernetes objects, often a source plus a `Kustomization` or `HelmRelease` per input. Its own docs example generates "a Flux HelmRelease and OCIRepository for each tenant". [docs]

- One status. The `ResourceSet` has one `Ready` condition. It keeps one inventory in `.status.inventory` for everything it applied, with entries like `apps_podinfo_helm.toolkit.fluxcd.io_HelmRelease`. The generated Flux objects keep their own status. [docs]
- Inputs. `.spec.inputs` holds inline values, read in templates as `<< inputs.name >>`. The `<< >>` delimiters replace `{{ }}`. `.spec.inputsFrom` takes `ResourceSetInputProvider` objects. The provider types include `Static`, `GitHubPullRequest`, `GitHubTag`, `OCIArtifactTag` and `ExternalService`. [docs] https://fluxoperator.dev/docs/crd/resourcesetinputprovider/
- Ordering. `.spec.dependsOn` refers to outside objects (CRDs, other `ResourceSet` objects). It does not order the generated objects. [docs] For that, put `dependsOn` in the generated `Kustomization`, or use `.spec.steps`. [inference]
- `steps`. Optional, at most 20, and mutually exclusive with `resources` and `resourcesTemplate`. After each step the operator waits for the step's resources to be ready, "regardless of the .spec.wait setting". If a step fails, "the subsequent steps are not applied". Garbage collection runs only after all steps pass. [docs]
- Deletion order. The docs say: "There are no guarantees about the order with which step-defined resources are terminated when the ResourceSet is deleted or when resources are removed from the steps." They add: "We reserve the right to define and change the termination order in future releases." [docs] So `steps` orders creation. It does not promise the reverse order on delete.
- Garbage collection. On delete, the operator first deletes the Flux custom resources and waits (at most one minute) for the `Kustomization` and `HelmRelease` objects to finalize. Then it deletes the rest. [docs]

### Example

The same two addon leaves as one `ResourceSet`. It follows the `resourcesTemplate` pattern in the docs (an `OCIRepository` and `Kustomization` from inputs). A group `Kustomization` can apply this file in place of the leaf files. [docs] [inference]

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSet
metadata: {name: addons, namespace: flux-system}
spec:
  wait: true
  inputs:
    - {name: cert-manager, tag: 1.0.0, dependsOn: ""}
    - {name: external-secrets, tag: 1.0.0, dependsOn: cert-manager}
  resourcesTemplate: |
    ---
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: OCIRepository
    metadata: {name: << inputs.name >>, namespace: flux-system}
    spec:
      interval: 5m
      url: oci://ghcr.io/example-org/demo/<< inputs.name >>
      ref: {tag: << inputs.tag | quote >>}
    ---
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata: {name: << inputs.name >>, namespace: flux-system}
    spec:
      <<- if inputs.dependsOn >>
      dependsOn:
        - name: << inputs.dependsOn >>
      <<- end >>
      interval: 10m
      retryInterval: 1m
      timeout: 5m
      prune: true
      wait: true
      path: ./
      sourceRef: {kind: OCIRepository, name: << inputs.name >>}
```

`flux-schema validate` accepted this with the ecosystem catalog. I did not render the template, because the `flux-operator` CLI is not installed here. The empty-string `dependsOn` and the `if` on it rest on standard Go template rules. [inference]

## 3. The Flux docs' own repository structure

The "Ways of structuring your repositories" guide shows the monorepo layout `apps/`, `infrastructure/`, `clusters/<name>`. It says "Each cluster state is defined in a dedicated dir e.g. clusters/production" and "The separation between apps and infrastructure makes it possible to define the order in which a cluster is reconciled, e.g. first the cluster addons and other Kubernetes controllers, then the applications." It points to `flux2-kustomize-helm-example` as the full example. [docs] https://fluxcd.io/flux/guides/repository-structure/

The guide has no `dependsOn` YAML. The example repo has it. `clusters/staging/infrastructure.yaml` defines `infra-controllers` (`wait: true`) and `infra-configs` (`dependsOn: infra-controllers`). `apps.yaml` defines `apps` with `dependsOn: infra-configs`. The README says: "with `dependsOn` we tell Flux to first install or upgrade the controllers and only then the configs". [repo-example] https://github.com/fluxcd/flux2-kustomize-helm-example

Note one detail of the current example. Its Kustomizations use `sourceRef: ExternalArtifact`. An `ArtifactGenerator` in `clusters/staging/artifacts.yaml` splits the one monorepo into `infrastructure` and `apps` artifacts. So the docs shape now has a generated source per group, not a plain `GitRepository`. [repo-example]

## 4. Mapping and lifecycle differences

- Application to Flux. The guide's "Repo per app" section shows the pairs `GitRepository` plus `Kustomization` and `HelmRepository` plus `HelmRelease`. An Argo `Application` bundles the source, the path and the target in one object. Flux splits them. [docs] [inference]
- Cascade on delete. Argo: "If you want to ensure that child-apps and all of their resources are deleted when the parent-app is deleted make sure to add the appropriate finalizer". Flux: `deletionPolicy` defaults to `MirrorPrune`, "deleted if prune is true and orphaned if false". Other values are `Delete`, `WaitForTermination` and `Orphan`. [docs]
- Escape hatch. The annotation `kustomize.toolkit.fluxcd.io/prune: disabled` on an object excludes it from garbage collection. Part 3 puts it on the `FluxInstance`. [docs] [repo: `clusters/kind/flux-instance.yaml` line 11]
- Suspend. `.spec.suspend` stops new revisions and drift correction for that `Kustomization`. The docs say nothing about children. A child is its own object, so it keeps reconciling. To freeze a group, suspend each child. [docs] [inference]
- Admin risk. Argo warns that the parent source is admin-level. In Flux the equivalent control is `serviceAccountName` on each `Kustomization`, as `flux2-multi-tenancy` and `d1-fleet` set it. [repo-example] [inference]

## 5. Part 3 against the docs shape

Matches. [repo]
- The `FluxInstance` is the installer and not a node of the tree. Its `spec.sync` has `kind: GitRepository` and `path: code/mcp-sandbox/part-3-mcp-guardrails/sync/local-kind` (lines 23-27). The Flux Operator makes the source and `Kustomization` named `flux-system`. [docs] https://fluxoperator.dev/docs/crd/fluxinstance/
- The root path holds `apps.yaml` with three group `Kustomization` objects: `secrets`, `mesh` and `gateway`. Each group sets `prune: true` and `wait: true`.
- Each unit has its own `dependsOn`, as in the docs chain. `gateway/stack.yaml` has 7 units, 6 with `dependsOn`. One edge crosses a group boundary: `mcp-servers` in `gateway` waits for `secret-store` in `secrets`.

Differs. [repo]
- Generated pinned stack file. `infra/<group>/stack.yaml` starts with "GENERATED by stack-composer (tools/): do not edit by hand". The docs shape uses hand-written files.
- One OCI artifact per unit. Each unit is an `OCIRepository` with `ref.digest` and `ref.tag` plus a `Kustomization` with `path: ./`. The docs example uses a path in one Git repo, or an `ExternalArtifact`.
- No per-group source. The group `Kustomization` objects use the `GitRepository` `flux-system`. The units carry the OCI sources. In `d1-fleet` the group (tenant) path also holds its source.
- Sources and `Kustomization` objects share one file per group. The units are not split into one file each.
- Groups follow dependency chains, not the Flux-docs split of infrastructure and apps. A component joins a group with the label `app.kubernetes.io/part-of` in its entry file.
- No group-level `dependsOn`. Groups share one `GitRepository`, so a group-level `dependsOn` makes the dependent group wait for each new revision of the other. A spike on a live cluster showed this.
- The groups set `deletionPolicy: Orphan`. The docs example does not. A spike showed that deleting a group with the default policy deleted all its units at once, and with Orphan the units stayed.
- No `serviceAccountName` and no `ResourceSet`.
- The group `timeout` must exceed the longest unit chain that the group waits for. `gateway` is 25m (see `apps.yaml`).

## Gaps

- `fluxoperator.dev/docs/resourcesets/resourcesets/` and `.../resourcesetinputprovider/` returned HTTP 404. I used the `/docs/crd/` pages instead. I read the `d1-fleet` repo files and not its docs pages on fluxoperator.dev.
- The Flux docs do not say what suspending a parent does to child `Kustomization` objects. My statement is an inference from the object model. The same holds for "deleting a parent deletes the children". No page states it for the nested case.
- The repository-structure guide has no `dependsOn` chain. The `infra-controllers` then `infra-configs` then `apps` chain comes from the example repo, and that repo now uses `ExternalArtifact`.
- The Argo CD page shows the `Application` fields only through its examples. The mapping of an `Application` to source plus `Kustomization` is my reading.
- I did not render the `ResourceSet` template and did not run any example on a cluster.
- I did not read the defaults of the `flux-system` `Kustomization` that the `FluxInstance` generates (for example its `prune` and `wait`).
