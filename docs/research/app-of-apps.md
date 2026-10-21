# The app-of-apps pattern, and how part 3 applies it with Flux

Question: What is the app-of-apps pattern, does `code/mcp-sandbox/part-3-mcp-guardrails` apply it with Flux, and what does an app level give that the flat stack did not?

Source: the Argo CD "Cluster Bootstrapping" page (fetched) and the Flux `Kustomization` API page (fetched), both on 2026-10-21. Repo claims are tagged **[repo]** with file and line at `main` `5b5997c`. My own conclusions are tagged **[inference]**.

## Verdict

1. The pattern comes from Argo CD. One parent `Application` holds a folder of child `Application` objects. Applying the parent creates all children. The Argo CD docs call it "(Alternative)" and recommend `ApplicationSet` first. The docs also say only admins should have push access to the parent source, because a parent can create `Application` objects in any project. [docs: Argo CD]
2. Flux has no `Application` kind. The same shape is a `Kustomization` that applies a folder of `Kustomization` objects. Each child has its own `prune`, `wait`, `timeout` and `dependsOn`. [inference]
3. Before this change, part 3 had a root and 13 units and no app level. The `FluxInstance` is the installer and not a node of the tree. [repo: `clusters/kind/flux-instance.yaml`, `sync/local-kind/infra-stack.yaml`]
4. After this change, the root applies two apps, `addons` (10 units) and `policies` (3 units). `policies` waits for `addons`. A third app, the first real workload, is one more entry in `apps.yaml`. [repo: `sync/local-kind/apps.yaml`]

## What the Flux docs say about the parts that matter here

- `dependsOn`: a `Kustomization` applies only after the `Kustomization` objects it names have the `Ready` condition. This is how `policies` waits for `addons`, and the same field orders the units. [docs: Flux]
- `prune` and deletion: when a `Kustomization` is deleted, Flux removes the objects it applied. The default `deletionPolicy` is `MirrorPrune`: the objects are deleted when `prune` is `true`. The annotation `kustomize.toolkit.fluxcd.io/prune: disabled` on an object excludes it. [docs: Flux]

## What an app level gives

| Need | Before | After |
|---|---|---|
| Suspend, or check health of, a group | Per unit, 13 times | `flux suspend ks policies`; one `Ready` condition per app |
| Order two groups | `dependsOn` on every unit | `dependsOn: addons` on the `policies` app (the unit `dependsOn` stay) |
| Add a workload after the platform | A new unit in the one stack | A new app that waits for `addons` and `policies` |
| Different permissions per group | Not possible | `serviceAccountName` on an app. **Not done in this change.** |

## Cost

- Moving the 13 units from the root to the apps makes the root prune them. A deleted unit with `prune: true` can delete its workloads, so migrate by recreating the kind cluster, or protect the units first with the annotation above. [docs: Flux] [inference]
- `stack-composer` writes one stack file per run. A `dependsOn` across the two stacks needs `--also <stack.yaml>`, otherwise the check fails or misses a waiter. [repo: `tools/stack-composer/stack_composer.py`]
- An app `timeout` must exceed the longest `dependsOn` chain of its units. `addons` has a 20-minute chain (cert-manager, external-secrets, secret-store, mcp-servers, routes), so its timeout is 25 minutes. [repo: `sync/local-kind/apps.yaml`]

## Gaps

- Four components have no `flux/stack.yaml` and are not delivered: `platform/ext-mcp`, `ext-mcp-checks`, `ext-mcp-isolation`, `mcp-mtls`. The owner of the repo marked them out of scope. [repo]
- The orchestration diagram (`docs/diagrams/orchestration.drawio`) still shows 10 units and no app level. It needs a redraw in draw.io. [repo]
- I did not run the change on a kind cluster. Only `kustomize build`, the object-parity check and four `stack-composer` cases ran.
