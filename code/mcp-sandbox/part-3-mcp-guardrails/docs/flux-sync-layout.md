# Flux sync layout: research

Question: should the Flux install (`FluxInstance`), the infrastructure stack and the application stack be separate syncs? Each cluster or region needs its own sync folder.

Date of the research: 2026-10-16. Every claim has its source. A claim without a source in the Flux documents is marked **not found**.

## Decision

One sync folder for each cluster, named by its full placement. The two stacks are in it. Flux itself is apart, outside the folder:

```text
sync/local-kind/                   what Flux reconciles
├── kustomization.yaml
├── infra-stack.yaml               the components of platform/addons
└── app-stack.yaml                 every other component
clusters/kind/flux-instance.yaml   Flux itself: not in the synced folder
```

- The folder name is `sync:` in `clusters/<cluster>/cluster.yaml`. A later region is for example `sync/aws-dev-us-east-1/`.
- The tier of a component is its folder: `platform/addons/` is infrastructure.
- One owner and one service account (cluster-admin) still apply to all of it. The split is for order, for clarity and for a later second owner. It is not a permission boundary yet.
- **The `FluxInstance` is outside the synced folder.** The sources do not settle this (section 6): the Flux example and the ControlPlane reference keep it in the synced folder, and nothing forbids the other way. It was chosen because a merge cannot then remove it, deleting it uninstalls Flux, and the first apply of a `FluxInstance` is outside Git in any case. The cost: a Flux upgrade is a host step (`just clusters/kind/up`), not a merge.
- The sections below are the research. Section 3 describes the layout before the move (`clusters/kind/sync/`).

## 1. Answer in short

| Piece | Practice in the sources | For Part 3 |
|---|---|---|
| Flux install (`FluxInstance`) | One for each cluster. It lives in the folder of that cluster, apart from the workloads. | Separate it from the stack: its own folder, its own sync unit. |
| Infrastructure and applications | Separate `Kustomization` objects, ordered by `dependsOn`. Separate repositories only when different teams own them. | Keep them as separate units in one stack for now. Split into two stacks when a second owner or a restricted service account exists. |
| Each cluster or region | One folder for each cluster. Differences by overlays or by inputs. | One sync folder for each cluster, with a unique full name. |

## 2. What the sources say

### 2.1 One folder for each cluster

- Flux guide, monorepo: "Each cluster state is defined in a dedicated dir." The example has `clusters/production` and `clusters/staging`, next to `apps/` and `infrastructure/`.
  Source: <https://fluxcd.io/flux/guides/repository-structure/>
- The Flux example repository puts the Flux configuration of each cluster in `clusters/<name>/`. Each cluster is bootstrapped with its own `--path`.
  Source: <https://github.com/fluxcd/flux2-kustomize-helm-example>
- The multi-tenancy example says: "The repository structure mirrors the cluster fleet."
  Source: <https://github.com/fluxcd/flux2-multi-tenancy>
- **Regions: not found.** The Flux guide does not mention regions. A folder name that holds the region is a choice, not a rule of Flux.

### 2.2 The FluxInstance: one for each cluster, in its own place

- The Flux Operator allows one `FluxInstance` in a cluster, named `flux`. The sync examples use a path of one cluster, such as `clusters/my-cluster`.
  Source: <https://fluxoperator.dev/docs/crd/fluxinstance/>
- The `sync` field makes the operator create a source and a `Kustomization`. The default name is the namespace name (`flux-system`), the same as `flux bootstrap`. The `name` field cannot change after creation.
  Source: <https://fluxoperator.dev/docs/crd/fluxinstance/>
- Deleting the `FluxInstance` uninstalls Flux "without affecting any Flux-managed workloads".
  Source: <https://fluxoperator.dev/docs/crd/fluxinstance/>
- The reference architecture of ControlPlane (the authors of the operator) keeps it in `clusters/<name>/flux-system/flux-instance.yaml`. Its fleet repository holds the cluster folders and the tenant definitions only. Infrastructure and applications are in two other repositories. After bootstrap, changes go to this file, and "there is no need to run bootstrap again".
  Source: <https://github.com/controlplaneio-fluxcd/d2-fleet>
- **Not found:** a statement on whether the `FluxInstance` belongs inside the synced path or outside it. The documents are silent.

### 2.3 Infrastructure and applications: separate units, ordered

- Flux guide: "The separation between apps and infrastructure makes it possible to define the order in which a cluster is reconciled." Cluster add-ons and controllers go first.
  Source: <https://fluxcd.io/flux/guides/repository-structure/>
- In the example repository, each cluster folder holds three files: `artifacts.yaml`, `infrastructure.yaml` and `apps.yaml`. The units are `infra-controllers`, then `infra-configs` (`dependsOn: infra-controllers`), then `apps` (`dependsOn: infra-configs`). The reason: the configs need the CRDs that the controllers install, so "the Kubernetes CRDs are registered on the cluster, before Flux applies any custom resources".
  Source: <https://github.com/fluxcd/flux2-kustomize-helm-example>
- The separation of the tiers is by ordering and by who owns them, not by one folder for each tier.

### 2.4 Separate repositories when the owners differ

- Platform administrators have "unrestricted access to Kubernetes API". They install Flux, add CRDs and controllers, and create the tenant namespaces and RBAC. Tenants work under a service account that the administrators assign.
  Source: <https://fluxcd.io/flux/installation/configuration/multitenancy/>
- The `flux-system` sync runs as a cluster-admin service account.
  Source: <https://fluxcd.io/flux/installation/configuration/multitenancy/>
- In the ControlPlane reference, the applications repository "can't contain Kubernetes cluster-wide definitions such as CRDs, Cluster Roles, Namespaces". The platform team owns the fleet and infrastructure repositories. The development teams own the applications.
  Sources: <https://github.com/controlplaneio-fluxcd/d2-apps>, <https://github.com/controlplaneio-fluxcd/d2-infra>
- In the multi-tenancy example, the cluster folder holds `policies.yaml` and `tenants.yaml`. The tenants wait for the policies. "With `dependsOn` we tell Flux to apply the policies before reconciling the tenants."
  Source: <https://github.com/fluxcd/flux2-multi-tenancy>

### 2.5 How each cluster differs

- Flux guide: a `base` folder and one overlay folder for each environment.
  Source: <https://fluxcd.io/flux/guides/repository-structure/>
- ControlPlane reference: overlays for `staging` and `production`, and one OCI repository for each component. Staging follows the tag `latest`. Production follows `latest-stable`. Rollback moves a tag. The infrastructure `ResourceSet` takes the inputs `tenant`, `tag` and `environment` for each component.
  Source: <https://github.com/controlplaneio-fluxcd/d2-fleet>
- Each component of that reference is its own OCI artifact, with `controllers` and `configs` folders inside it.
  Source: <https://github.com/controlplaneio-fluxcd/d2-infra>

## 3. How Part 3 compares

| Topic | The sources | Part 3 now |
|---|---|---|
| Folder for each cluster | Yes | Yes: `clusters/kind/sync/` |
| FluxInstance apart from the workloads | Own folder (`flux-system/`) in the cluster folder | Same folder and same `Kustomization` as the stack. It is also in the prune scope of the sync. |
| Infrastructure before applications | Separate `Kustomization` objects with `dependsOn` | Yes: one `Kustomization` for each component, with `dependsOn` |
| One artifact for each component | ControlPlane reference: yes | Yes |
| Separate owners | Separate repositories and service accounts | One owner. Every unit runs as cluster-admin. |

## 4. Options for the layout

Names in this table: infrastructure is `gateway-api`, `agentgateway`, `spire`, `istio`. The rest (`istio-ingress`, `mcp-servers`, `routes`, the policies) is the application side. Your split may differ.

| Option | Layout of one cluster folder | Gain | Cost |
|---|---|---|---|
| A. Everything in one stack (now) | `stack.yaml` and `flux-instance.yaml` together | Smallest | The `FluxInstance` is in the prune scope of the stack sync. A path move can stop Flux (see 5). |
| B. Flux apart (recommended now) | `flux-system/flux-instance.yaml`, and `stack.yaml` | The install has its own life cycle and unit. The stack cannot touch it. One stack, so the composer is unchanged. | A second folder to explain |
| C. Three units, as in the Flux example | `flux-system/`, `infrastructure.yaml`, `apps.yaml` | The same shape as the Flux guides. It is ready for a second owner. | Two stack files. The composer, the entry files and the `dependsOn` check must know the tier. Each unit applies under cluster-admin, so no gain in permissions today. |
| D. Separate repositories | Fleet, infrastructure and apps in three repositories | Different teams, different access | A lot of work. It is for several teams. |

Recommendation: B now, and C when a second owner or a restricted service account exists.
Reason: the sources separate the tiers by ordering (`dependsOn`, which you already have) and by owner. You have one owner. The `FluxInstance` is the only piece with a clear reason to be apart: it has its own life cycle, its name cannot change, and deleting it uninstalls Flux.

## 5. Risk of moving the sync folder

The `flux-system` sync of this repository has `path` set to `clusters/kind/sync` and `prune: true` (read from the live cluster). The `FluxInstance` is a file in that same folder. If one merge removes the old folder and changes the path, Flux cannot find the old path in the new revision, and it stops before it reads the new `FluxInstance`. Re-apply the new `FluxInstance` on the host right after the merge, or copy the folder first and remove the old one later.
Objects that are in both the old and the new folder are not pruned, because their inventory stays the same.
This risk is from the behavior of Flux with a missing path. I did not test it.

## 6. Not found in the sources

- A rule for the name of a region folder.
- Whether the `FluxInstance` belongs inside or outside the synced path.
- A rule that infrastructure and applications need separate sync folders. The sources use separate `Kustomization` objects and, for separate owners, separate repositories.
- How the ControlPlane reference orders the units of different repositories. Its documents do not name the mechanism.
