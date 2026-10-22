# The app-of-apps pattern, and how part 3 applies it with Flux

Question: What is the app-of-apps pattern, does `code/mcp-sandbox/part-3-mcp-guardrails` apply it with Flux, and what does a group level give that the flat stack did not? Which problem does the pattern solve, does Argo CD recommend it, and how do the groups show in the Flux Operator Web UI?

Source: the Argo CD "Cluster Bootstrapping" page (fetched) and the Flux `Kustomization` API page (fetched), both on 2026-10-21. On 2026-10-22 I added the Argo CD pages "Declarative Setup" and "ApplicationSet Use Cases" (fetched). For Flux Operator 0.61.0 I added the web page <https://fluxoperator.dev/web-ui/>, the FluxInstance page, and the files `docs/web/*.md`, `web/src/*` and `internal/web/resource.go` at tag `v0.61.0` of <https://github.com/controlplaneio-fluxcd/flux-operator>. The chart `flux-operator` 0.61.0 is in <https://github.com/controlplaneio-fluxcd/charts> at commit `13f8768`. Repo claims are tagged **[repo]** with file and line at `main` `5b5997c`. My own conclusions are tagged **[inference]**. The tag **[docs: Flux Operator]** also covers the web source and the chart at that version.

## Verdict

1. The pattern comes from Argo CD. One parent `Application` holds a folder of child `Application` objects. Applying the parent creates all children. The Argo CD docs call it "(Alternative)" and recommend `ApplicationSet` first. The docs also say only admins should have push access to the parent source, because a parent can create `Application` objects in any project. [docs: Argo CD]
2. Flux has no `Application` kind. The same shape is a `Kustomization` that applies a folder of `Kustomization` objects. Each child has its own `prune`, `wait`, `timeout` and `dependsOn`. [inference]
3. Before this change, part 3 had a root and 13 units and no app level. The `FluxInstance` is the installer and not a node of the tree. [repo: `clusters/kind/flux-instance.yaml`, `sync/local-kind/infra-stack.yaml`]
4. After this change, the root applies three groups: `secrets` (3 units), `mesh` (3 units) and `gateway` (7 units). A group holds a chain of units that depend on each other, a CRD provider with the units that use it. The groups do not wait for each other. The units name what they need in their own `dependsOn`, also across the groups. The only edge between two groups is `mcp-servers` (in `gateway`) to `secret-store` (in `secrets`). A new group for the first real workload is one more entry in `apps.yaml`. [repo: `sync/local-kind/apps.yaml`]

## What the Flux docs say about the parts that matter here

- `dependsOn`: a `Kustomization` applies only after the `Kustomization` objects it names have the `Ready` condition. The same field orders the units, also across the two stacks. [docs: Flux]
- `prune` and deletion: when a `Kustomization` is deleted, Flux removes the objects it applied. The default `deletionPolicy` is `MirrorPrune`: the objects are deleted when `prune` is `true`. The annotation `kustomize.toolkit.fluxcd.io/prune: disabled` on an object excludes it. [docs: Flux]

## What a group level gives

| Need | Before | After |
|---|---|---|
| Check health of a group | Per unit, 13 times | One `Ready` condition per group (`wait: true`) |
| Order two groups | `dependsOn` on every unit | The unit `dependsOn` stay and also work across the groups. No group-level `dependsOn` (see Cost) |
| Add a workload after the platform | A new unit in the one stack | A new group. Its units name what they need |
| Different permissions per group | Not possible | `serviceAccountName` on a group. **Not done in this change.** |

## Cost

- Moving the 13 units from the root to the groups makes the root prune them. A deleted unit with `prune: true` can delete its workloads, so migrate by recreating the kind cluster, or protect the units first with the annotation above. [docs: Flux] [inference]
- A `dependsOn` between two groups that share one `GitRepository` makes the dependent group wait until the other group has applied each new revision. A spike showed `revision is not up to date` and about 30 s for each retry. So the groups have no `dependsOn` on each other. [spike, 2026-10-21]
- `stack-composer` writes one stack file per run. A `dependsOn` across the two stacks needs `--also <stack.yaml>`, otherwise the check fails or misses a waiter. [repo: `tools/stack-composer/stack_composer.py`]
- Flux does not delete in `dependsOn` order, and the Flux docs describe `deletionPolicy` for one `Kustomization` only. Deleting a group with the default `MirrorPrune` would delete all its units at once. [inference] The groups set `deletionPolicy: Orphan`, so deleting a group leaves its units running. A unit that leaves its stack is still pruned. [docs: Flux]
- Suspending a group does not suspend its units. A suspended `Kustomization` stops applying new revisions and stops drift correction for itself only. The unit `Kustomization` objects keep reconciling. To freeze a group, suspend each unit. [docs: Flux]
- A group `timeout` must exceed the longest `dependsOn` chain that the group waits for, including a chain in another group. `gateway` waits for `secrets` (13 minutes) and then runs `mcp-servers`, `routes` and `authn-jwt` (23 minutes in total), so its timeout is 25 minutes. [repo: `sync/local-kind/apps.yaml`]
- The folder of a component under `platform/` no longer decides its group. The label `app.kubernetes.io/part-of` on the `Kustomization` of its entry file does. [repo: `lib/workflow/common.just`]

## The problem the pattern solves, and what Argo recommends

A new cluster needs many apps. Argo CD names the options: "you could write a script to create your apps, or you could even manually create them". [docs: Argo CD] App of apps replaces that work with "one Argo CD app that consists only of other apps". To add an app, you add a file to the parent folder in Git. [docs: Argo CD] [inference] The owner's premise, "Argo recommends app of apps", is not correct. The same page says: "Our recommendation is to look at ApplicationSets and more specifically the cluster generator which can handle most typical scenarios". Its headings are "Application Sets and cluster labels (recommended)" and "App Of Apps Pattern (Alternative)". [docs: Argo CD] Argo presents app of apps for cluster bootstrapping: the page is for operators with "a new cluster" who want "many apps". The "Declarative Setup" page adds that it manages "a group of apps that can be deployed and configured in concert". [docs: Argo CD] The "ApplicationSet Use Cases" page names a second use, self-service by development teams. It then warns that admins must vet each commit that changes an `Application`, and it offers `ApplicationSet` as the safer way. [docs: Argo CD] So the reason to use it in part 3 is ours: it groups units that differ in content. [inference]

| | Before | After |
|---|---|---|
| Tree | `flux-system` applies 13 units | `flux-system` applies 3 groups, each group applies its units |
| Health view | 13 objects | 3 objects, one `Ready` condition each |
| Bootstrap | One `kubectl apply` of the `FluxInstance` | The same. The group level adds grouping and not bootstrap. |

[repo: `sync/local-kind/apps.yaml`, `clusters/kind/flux-instance.yaml`] [inference]. For the Flux terms, see `flux-app-of-apps-equivalent.md`.

## Seeing the groups in the Flux Operator Web UI

The Web UI is in Flux Operator 0.61.0 and the chart turns it on by default. Chart 0.61.0 sets `web.enabled: true`, the Deployment sets `WEB_SERVER_PORT=9080`, and the Service exposes port 9080 (`http-web`). [docs: Flux Operator] `clusters/kind/justfile` installs that chart with no values, so the UI should already run. It needs no change to the justfile. [repo] [inference] I did not run any step below, because the kind cluster is host-only.

1. Run all commands on the host. Use the context `kind-<cluster name>` (the justfile sets `ctx := 'kind-' + name`). [repo]
2. Check the Service: `kubectl --context kind-<name> -n flux-system get svc flux-operator`. The output should list `9080/TCP`. [docs: Flux Operator]
3. Forward the port: `kubectl --context kind-<name> -n flux-system port-forward svc/flux-operator 9080:9080`. [docs: Flux Operator]
4. Open `http://localhost:9080` in a browser on the host. There is no login. With no `web.config`, the UI has no authentication and gives read-only access. It does not show Secrets or ConfigMaps. [docs: Flux Operator]
5. Do not expose the port beyond the port-forward, because there is no authentication. Reconcile, suspend and resume actions need authentication, so they are not enabled. [docs: Flux Operator]
6. Choose Search, set the kind to `Kustomization` and the namespace to `flux-system`. Open `flux-system`, then Managed Objects, then Graph. Click a node to go down one level.

| View (v0.61.0) | What it shows | For part 3 |
|---|---|---|
| Cluster dashboard | Controller status, counts of Kustomizations, HelmReleases and sources | Count of `Kustomization` objects. It should be 17 (1 root, 3 groups, 13 units) if every unit exists. [inference] |
| Search | A flat list with status, filter by kind, namespace, status, name | All 17 in one list with no group column. Filter by `Failed` to find a broken unit. [docs: Flux Operator] |
| `FluxInstance` `flux`, Graph | A `Distro` node, then a "Flux Resources" group from its inventory | The top of the tree. The group should hold the root `GitRepository` and `Kustomization` `flux-system`. [inference] |
| `Kustomization` `flux-system`, Graph and Inventory | `GitRepository`, then the `Kustomization`, then "Flux Resources (N)" with a status word per item | The root. N should be 3: `secrets`, `mesh`, `gateway`. [repo: `apps.yaml`] [inference] |
| `Kustomization` `gateway`, Graph and Inventory | The same layout, one level down | The group. "Flux Resources" counts units and their `OCIRepository` objects: 14 for `gateway`, 6 for `secrets`, 6 for `mesh`. [repo: `stack.yaml` files] |
| Group `Ready` condition | The status card at the top, then Reconciler, Overview (status badge, message), then the Status tab (YAML with `conditions`) | The `Ready` of `gateway`. Managed Objects, Overview shows "Garbage collection" and "Health checking" as Enabled for `prune: true` and `wait: true`. [docs: Flux Operator] |
| Unit, Reconciler, Overview | A "Managed by" link built from the labels `kustomize.toolkit.fluxcd.io/name` and `/namespace` | `mcp-servers` should link to `Kustomization/flux-system/gateway`. That is the unit-to-group edge. [docs: Flux Operator] [inference] |
| Unit, Reconciler, Specification | The `spec` as YAML | The cross-group edge: `mcp-servers` has `dependsOn: agentgateway, secret-store`. It shows as text only. [repo] [docs: Flux Operator] |
| Unit, Reconciler, Events and History, and the Event viewer | Events and revisions per resource, and a live event stream | Each retry of a waiting unit. Not aggregated by group. [docs: Flux Operator] |

What the UI cannot show:

- It does not draw a `dependsOn` edge. The Graph draws only source, reconciler and inventory. I read `GraphTabContent.jsx`, `ReconcilerPanel.jsx` and `ManagedObjectsPanel.jsx` at the tag and found no `dependsOn` code. A code search found `dependsOn` only in `web/src/mock/resource.js`. The search covered the default branch and not the tag. [docs: Flux Operator]
- So `secret-store` has no "waited on by `mcp-servers`" view. You must open the Specification of `mcp-servers`. [inference]
- It does not show the whole tree on one screen. Each Graph shows one level, so root to unit takes three clicks. [docs: Flux Operator]
- `deletionPolicy: Orphan` on a group appears only in the Specification YAML. The Overview shows prune, wait and decryption. [docs: Flux Operator]
- The page polls every 30 seconds (`POLL_INTERVAL_MS`), so a status may lag. [docs: Flux Operator]

## Gaps

- Argo CD gives no reason to choose app of apps over `ApplicationSet`, beyond bootstrapping and the self-service case with its warning. No other Argo CD page that I fetched gives one. [docs: Argo CD]
- I did not run the Web UI steps. The 17, 14 and 6 counts and the "Managed by" link come from reading the source and the repo files. [inference]
- <https://fluxoperator.dev/docs/web-ui/> returned HTTP 404. I used the web README and the docs files at the tag. The network policy blocked no host.
- The charts repo has no tag `v0.61.0`. I matched `Chart.yaml` `version: 0.61.0` to commit `13f8768`. I did not inspect the published OCI package.
- The namespace dropdown depends on `get` for `ResourceSet`. I did not check what the default identity sees. [docs: Flux Operator]
- Four components have no `flux/stack.yaml` and are not delivered: `platform/ext-mcp`, `ext-mcp-checks`, `ext-mcp-isolation`, `mcp-mtls`. The owner of the repo marked them out of scope. [repo]
- The orchestration diagram (`docs/diagrams/orchestration.drawio`) still shows 10 units and no group level. It needs a redraw in draw.io. [repo]
- I did not run the change on a kind cluster. Only `kustomize build`, the object-parity check and four `stack-composer` cases ran.
