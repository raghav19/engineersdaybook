# Secrets of cluster `kind`

Flux decrypts the files in this folder with the age key in the Secret `sops-age` (flux-system). Only ciphertext belongs here. No artifact and
no rendered manifest holds a secret: the Backend refers to the Secret `github-upstream` by name.

## Create `github-upstream.sops.yaml` (once, on the host)

The token is in `.env.secrets.json`. The sandbox VM never has it, and neither does the age key.

1. Create the key for this cluster, outside Git: `age-keygen -o ~/.config/sops/age/mcp-guardrails-kind.agekey`
2. Add a rule for `clusters/*/sync/secrets/*.sops.yaml` to the repo `.sops.yaml`, above any rule that matches the same path. Use the public
   key (`age1...`) that `age-keygen` printed, and `encrypted_regex: ^(data|stringData)$`.
3. Build the Secret and encrypt it, without writing the plaintext to disk. Example (adjust the key name to your file):

   ```sh
   sops exec-env .env.secrets.json \
     'kubectl create secret generic github-upstream --namespace agentgateway-system \
        --from-literal=Authorization="$GITHUB_TOKEN" --dry-run=client -o yaml' \
   | sops --encrypt --filename-override clusters/kind/sync/secrets/github-upstream.sops.yaml \
       --input-type yaml --output-type yaml /dev/stdin \
   > clusters/kind/sync/secrets/github-upstream.sops.yaml
   ```
4. Add `kustomization.yaml` in this folder that lists `github-upstream.sops.yaml`, and commit both.

The ciphertext is public in Git. The repo already publishes `.env.secrets.json` the same way. Use a dedicated key for this cluster.
To move to remote references later, replace the file with an `ExternalSecret` of the same name (Bitwarden Secrets Manager). No consumer changes.
