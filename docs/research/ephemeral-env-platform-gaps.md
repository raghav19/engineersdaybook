# Platform of `code/ephemeral-env`: what the commands checked and what they did not

Question: Which parts of the platform in `code/ephemeral-env` did a command check, and which parts still wait for a first run on a cluster?

Source: the files in `code/ephemeral-env`, the Flux docs for the controller options (fetched), the `flux-schema` catalog, and the commands that I ran in the sandbox. No command ran against a cluster. Research date: 2026-11-05.

## Verdict

1. All manifests of the platform and the bring-up pass `flux-schema validate`. `just check` runs the check, and it exits 1 on a bad manifest.
2. The recipes `publish` and `up` refuse to run in the sandbox VM. I ran both and read the refusal.
3. No part of the platform ran on a cluster. I verified none of the items under "Not checked".

## Checked by a command

- `just check` builds `platform/`, `platform/addons/*` and `platform/apps/*` with `kustomize`. It validates each result and `clusters/k3s/`.
- The Istio chart index lists the version `1.31.1` for `base` and `istiod`.
- The Boutique release file at the pinned commit renders 36 valid objects after the patch.
- `yq '.spec.sync.ref = strenv(REF)'` writes the tag into the `FluxInstance`.

## Not checked

- **Versions.** The Flux Operator 0.62.1 with Flux 2.10.0, and the Istio 1.31.1 charts on k3s 1.37.
- **The Traefik Gateway config.** Whether the k3s Traefik chart accepts the `HelmChartConfig` values on a fresh install. The same idea works on the current cluster of `code/platform-engineering`.
- **Registry access.** `flux push artifact --creds` against GHCR, and the GHCR rate limits.
- **The redirect of the Istio chart host.** `blob.istio.io` redirects, and source-controller must follow it.
- **Remote bases.** The Flux docs list the controller flag `--no-remote-bases`. They state no default. If the flag is on, `apps-boutique` fails to build.
- **Native sidecars.** The `loadgenerator` init container `frontend-check` needs the network before the main containers start. That works only if Istio injects the sidecar as a native sidecar.
- **Injection order.** Whether a pod that starts before the webhook exists receives any report. The ordered Kustomizations avoid the case.
- **Kiali view-only mode.** Whether `view_only_mode` hides every write action in the Kiali UI.
- **Memory.** The memory of one node for 12 pods with sidecars.
- **Image access.** The cluster pulls images from `quay.io`, `docker.io`, `ghcr.io` and `us-central1-docker.pkg.dev`.
- **The k3s install commands in the README.** They come from `code/mcp-sandbox/part-3-mcp-guardrails/clusters/k3s/justfile`. That recipe carries its own TODO: it did not run on a fresh install.
- **The expected output of the check commands in the README.** Nobody ran them.

## Open decisions

- **The result check of a sandbox.** The cluster runs on a laptop. A GitHub-hosted runner cannot reach it. The two options are a self-hosted runner (a risk on a public repo) and a Flux commit status.
- **Central config.** The user wants versions and settings in one config with setters, as in part 3. Part 3 does this with a Python tool and many recipes. The choice is to reuse those tools or to write a small `kustomize` setter.
- **Pull of sandbox images.** The plan is a k3s `registries.yaml`. It comes from memory and nobody checked it.
