---
status: accepted
---

# The host registers its entries under its own names

The node is the host that runs the microVMs. Its name in the SPIRE server is the host name of the machine, and not the name of a VM. The host creates its entries with `just msb host-register` and `just msb vm-register`, from templates, and not from files in git.

## Decision

- The node name is the host name in lower case. `MSB_NODE` in `.msb/justfile` holds it. A new host registers under its own name.
- `just msb host-register` creates three objects: the node certificate of the host, the node entry, and the delegate entry. The node entry gives the host agent the ID `spiffe://mcp.local/node/<host-name>`.
- `just msb vm-register` creates the entry of one VM. Its ID is `spiffe://mcp.local/node/<host-name>/user/<github-id>/vm/<vm-name>`. `just msb vm-unregister` and `just msb host-unregister` remove the objects.
- The host applies the templates in `.msb/k3s/` with `kubectl`. Flux does not apply them. The spire-controller-manager copies the `ClusterStaticEntry` objects into the server.
- The host agent has its own node certificate and its own node entry. The agent in the VM keeps its older certificate and its older node entry `sandbox-node`. The two agents do not share an ID.
- The recipes accept only names with 1 to 40 characters: lower case letters, digits and `-`. The names go into Kubernetes names and into a SPIFFE path.

## Considered options

- **Entries in git, with the names written out.** This is simple for one host and one VM. A SPIFFE ID in an entry is a fixed string, and a selector has one exact value. So each new VM or host needs a change in git and a new published artifact. The entries would also carry the name of a VM before the VM exists.
- **One entry for all VMs of a user, with no VM name.** The gateway could not tell the VMs apart. This loses the identity of each VM.
- **The node entry with the VM name `sandbox-dev`.** This was the first design, from the time when the microVM itself was the node. The host is the node now. A node that has the name of a VM is confusing.

## Consequences

- The objects are outside the inventory of Flux. Flux does not prune them, and it does not show a difference if someone edits them. Remove them with the unregister recipes.
- Only a person who has the kubeconfig of the host can register an identity. The VM has a read-only token, so a VM cannot register an identity for itself.
- A new host name is a new node. If you rename the host, run `host-register` again. The old node entry stays until you run `host-unregister` under the old name.
- `host-register` changes the cluster. Run it on purpose.
- The part 3 guides about the node attestation describe the agent in the VM, with the node `sandbox-dev`. They stay true for that agent until you retire it.
