## Summary

```diff
 .msb/image/configs/agent/gitconfig
+  [user]
+    name = Raghavender Nagarajan
+    email = raghavendern@hotmail.com
   [credential "https://github.com"]
-    helper = !f() { echo ...; echo ...; }; f
+    helper = "!f() { echo ...; echo \"...\"; }; f"

 .msb/image/mise.toml
   [env]
-    KUBECONFIG = "/run/sandbox/source/.msb/kubeconfig"  # stale kind path, not ported

 .msb/vm/sandbox.yaml
   network.allow:
+    - docs.k3s.io
```

## Evidence

- **Before (git):** `git config --get credential.https://github.com.helper` returns `!f() { echo username=x-access-token` (truncated at first `;`)
- **After (git):** returns the full `!f() { echo username=x-access-token; echo "password=$GH_TOKEN"; }; f`
- **Before (kubectl):** `mise activate bash` overrides `KUBECONFIG` with `/run/sandbox/source/.msb/kubeconfig` (does not exist). kubectl fails.
- **After (kubectl):** `KUBECONFIG` from `sandbox.yaml` (`/home/agent/.kube/config`) is no longer overridden. sandbox-boot writes the rewritten k3s kubeconfig there.

## Merge Danger

**Door:** two-way

Revert the gitconfig, mise.toml and sandbox.yaml changes to restore prior behaviour.

**Blast Radius:** sandbox image

Affects git credential helper, kubectl, and network policy inside the msb VM only. No host-side impact.
