# Handoff: delegated identity for the msb microVM (spike done)

Written on 2026-11-07. The index of all handoff documents is `docs/handoff.md` at the root of the repo.

This handoff continues `microvm-workload-attestation.md` in the same folder. The spike on the host answered its open questions. A fresh session can read this document and start the PRs.

**Where this document and an older record disagree, this document wins.** The old handoff lists Route A (a systemd unit) and four other routes. This work chose the Delegated Identity API with a pid and a custom plugin. Route A does not work as it stands (see "Facts checked on the host").

## Goal

Each microVM gets its own SPIFFE ID. The private key stays on the host, outside the guest. The SPIRE agent checks properties of the VM, and not properties of a forwarder.

```text
spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/<vm-name>
```

## Read these first (do not copy them here)

- The old handoff: `microvm-workload-attestation.md`.
- The research note: `docs/research/microvm-workload-attestation-spire.md`. It comes from reading only. The spike proved some of its claims and corrected others.
- The node attestation guide: `code/mcp-sandbox/part-3-mcp-guardrails/docs/node-attestation.md`.
- The spike code and configs: the section "The spike code" in this file. It is the code of a test. It is not production code.
- The repo rules: `AGENTS.md`. Read `docs/agents/pull-requests.md` before any commit or PR.

## The design (agreed with the user)

One host agent. One proxy process (the delegate). One custom plugin inside the agent. Two registration entries.

1. The proxy connects to `admin.sock` of the host agent.
2. The agent reads the pid of the caller from the kernel. It attests the proxy with its attesters. It matches the entry of the proxy and checks `authorized_delegates`.
3. The proxy sends the pid of the VMM (the `msb machine` process) in the request. It sends nothing else.
4. The agent runs its workload attesters on that pid. The `unix` attester gives the uid. The `msbvm` plugin gives the VM name and the sandbox ID.
5. The agent matches the entry of the VM. The selectors are `msbvm:name:<vm>` and `unix:uid:<uid>`.
6. The agent returns the SVID and the key to the proxy on a stream. The VM never sees them.

## Facts to keep straight

The user and I corrected these during the session. Do not repeat the old claims.

- The pid is the input of the attesters. It is not a selector, because it changes at each start.
- The plugin reads the name and the ID from the command line of the VMM. The `run` row in `msb.db` only checks them.
- The proxy has its own entry, and the agent mints an SVID for it. The `admin.sock` call does not deliver that SVID. The proxy gets it with a second call to `agent.sock`. I did not test that call.
- The agent mints the SVIDs of all entries of its node at start. The server is not involved when a delegate calls.
- A refusal is an empty response with zero SVIDs. It is not an error. The proxy must treat zero SVIDs as a failure.
- The Delegated Identity API runs on a local Unix socket only. The delegate must run on the same host as the agent.
- The API does not limit a delegate to certain VMs. Use one agent for each user in a multi-tenant host.
- A plugin must be in Go. The SPIRE SDK is Go only. The proxy can be in Go or in Python.

## Facts checked on the host (2026-11-06, live)

- msb is version 0.7.13. SPIRE is 1.15.5. systemd is 262. Go is 1.27.3 (mise). `spire-agent` is not installed on the host.
- `msb inspect` has no VM ID, no pid and no start time. It has the name, `created_at`, the image digest and a `config-sha` label that changes with the config.
- The VMM is the process `msb machine --name sandbox-dev --sandbox-id 184 ...`. Its parent is `systemd --user`. It has no child process.
- The VMM is also the network proxy. Threads `smoltcp-poll` and `virtio-net` run inside it. It holds `agent.sock` and `control.sock` under `~/.microsandbox/run/sandboxes/`.
- The VMM has no cgroup scope of its own. It runs in the scope of the terminal. The system D-Bus returns `user@1000.service` for its pid.
- `msb.db` has a `sandbox` table (the ID is an autoincrement) and a `run` table (pid, status, `started_at`). Each start adds a `run` row.
- The `run.started_at` value matches the start time in `/proc` within 5 ms.
- `spire.localhost` resolves on the host and the gateway answers. The server has `join_token` and `x509pop` enabled.

## Spike results

The spike used a throwaway SPIRE server on localhost. It did not use the cluster. The agent attested with a join token.

| Test | Result |
|---|---|
| T1: the delegate sends the real VMM pid | The SVID of the VM came back. The key parsed as ECDSA. |
| T2: a pid that is not a VMM | Zero SVIDs |
| T3: the same delegate binary at another path | `PermissionDenied: no identity issued` |
| T4: a fake `msb` with the same exe name and command line | Zero SVIDs. The plugin found no `run` row. |
| T5: the real VMM again | The same SVID came back. |

## Findings that change the design

- The admin socket must be in a different folder from the Workload API socket. The agent refuses to start otherwise.
- The host agent cannot share the `x509pop` node certificate with the agent in the VM. Both would get the same agent ID. I think they would remove each other from the server. I did not test it.
- The plugin depends on the `run` and `sandbox` tables of msb 0.7.13. These tables are internal and can change.
- A `join_token` agent cannot attest again. The agent warned about this with the `memory` key manager. The real setup uses `x509pop`.
- The spike has no `pidfd`. The proxy must hold a `pidfd`, so a recycled pid is never sent.

## Google Agent Compute Engine

Source: the post [Agent Compute Engine deep dive](https://cloud.google.com/blog/topics/ai-infrastructure/agent-compute-engine-deep-dive).

- One microVM for each agent. The keys for node and workload attestation stay "outside the guest environment within the IPU, the host, or remotely".
- The VM gets a session-scoped public SPIFFE certificate and a token. A local proxy forwards its traffic. The gateway checks the user, the agent identity and the node identity.
- The node anchor is Google silicon: Titan and the Titanium IPU. The post does not mention a TPM or TPU attestation. It does not say what evidence the attestation produces.
- Our design has the same shape. The attestation mechanics of Google are not public, so I cannot say they are equal.
- Option for later: the SPIRE node attestor `tpm_devid` puts the node key in a TPM. The host has `/dev/tpm0`. The device is open to root and the group `tss` only. I did not test `tpm_devid`.

## Plan: separate PRs

1. **Docs and ADR.** The answers of Step 1, the spike results and the decision. No code. Move this handoff and the spike archive here.
2. **The `msbvm` plugin.** A Go module with unit tests (a fake `/proc` and a fake database). Pin the tested msb version. Print the checksum of the binary.
3. **Host agent.** The agent config, a `just msb` recipe, a node certificate for the host, and the decision about the agent in the VM. Depends on PR 2.
4. **The proxy (delegate).** It finds the VMM pid, holds a `pidfd`, treats zero SVIDs as a failure and keeps the stream. Depends on PR 3.
5. **Registration.** A `ClusterStaticEntry` for the proxy and one for each VM. The alias is the parent. Use `gitops-knowledge` and the schema catalog. Can run in parallel with PR 4.
6. **Gateway.** The gateway reads the URI SAN and checks the node, the user and the VM. This has its own open problem (see the earlier handoff: the ExternalSecret `github-upstream` fails).

Do PR 1 and PR 2 first. A later PR can add `tpm_devid` for the node key.

## Open decisions (ask the user)

- The language of the proxy: Go or Python. I suggest Go. The repo rules for Python are in `docs/agents/python.md`.
- How the proxy finds the VMM pid. Option 1: it starts the VM and keeps the child pid. Option 2: it reads the `run` row in `msb.db`. I tested neither.
- The node certificate of the host agent: a separate certificate, or the VM agent goes away.
- The location of the code in the repo: under `code/mcp-sandbox/part-3-mcp-guardrails/`, or a new `tools/` folder.
- Does the proxy need its own SVID? If it does, it needs the second connection to `agent.sock`.
- What starts the proxy: `just msb run`, or a systemd user unit.
- The user has not decided to close PR #260 (Envoy in the VM).

## Cleanup on the cluster

My first attempt left two items on the SPIRE server of the cluster. I could not remove them, because the permission check blocked writes to the live server. Check first. Run these on `spire-server-0` in `spire-system`.

```text
spire-server entry show          # look for spiffe://mcp.local/spike/agent
spire-server agent list          # look for an agent with the type join_token
spire-server entry delete -entryID b5504c60-6d3d-4112-a3f0-fc378a86544a
spire-server agent evict -spiffeID <the join_token agent ID from the list>
```

The user may have removed them already. Do not touch the entries `mcp-guardrails.*` and the agents `k8s_psat` and `x509pop`.

## How to rebuild the spike

Run these on the host. Use an empty folder for the unpacked SPIRE release. Do not run an interpreter inside it.

1. Download the SPIRE release: `gh release download v1.15.5 -R spiffe/spire -p 'spire-1.15.5-linux-amd64-musl*'`. Check it with `sha256sum -c` on the `_sha256sum.txt` file. Unpack it.
2. Build the plugin and the delegate. Save each source file from "The spike code" in its own empty folder. Run the commands that the section gives.
3. Save the two configs from "The spike code". Fill the placeholders. Put the checksum of the plugin binary in the agent config.
4. Start `spire-server run`. Make a join token for `spiffe://mcp.local/spike/agent`. Keep the token in a file with mode 600.
5. Make two entries on the local server. Both have the parent `spiffe://mcp.local/spike/agent`. The proxy entry uses `unix:uid` and `unix:path` of the delegate binary. The VM entry uses `msbvm:name:<vm>` and `unix:uid`.
6. Start `spire-agent run` with the join token. Run `delegate -socket <admin.sock> -pid <VMM pid>`. Get the pid with `ps -eo pid,args | grep '[m]sb machine'`.

## The spike code

This is the code of the spike. It is not production code. PR 2 and PR 4 rewrite it with tests.

### The plugin

The plugin is a workload attestor with the name `msbvm`. It takes a pid and returns the selectors `name:<vm>` and `id:<sandbox-id>`. It needs three checks to agree:

- the exe of the process is `msb`
- the command line names the VM
- the `run` row in `msb.db` has the same pid and start time

Save the source as `main.go` in an empty folder. Build it with these commands:

```text
go mod init spike/msbvm
go get github.com/spiffe/spire-plugin-sdk@v1.4.4-0.20260617144146-5dcde407c4d1 github.com/hashicorp/hcl@v1.0.0 modernc.org/sqlite@v1.61.1 google.golang.org/grpc@v1.84.0
go mod tidy
go build -o msbvm .
```

<details>
<summary>plugin/main.go (159 lines)</summary>

```go
// Spike: WorkloadAttestor "msbvm". It maps a host pid to a microsandbox VM.
// Input is one pid. Output is the selectors name:<vm> and id:<sandbox-id>.
// Three checks must agree: the exe is msb, the command line names the VM,
// and the "run" row of msb.db has the same pid and start time.
package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/hashicorp/hcl"
	"github.com/spiffe/spire-plugin-sdk/pluginmain"
	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	_ "modernc.org/sqlite"
)

const maxStartSkew = 2 * time.Second

type Config struct {
	DBPath string `hcl:"db_path"`
}

type Plugin struct {
	workloadattestorv1.UnimplementedWorkloadAttestorServer
	configv1.UnimplementedConfigServer
	mu  sync.RWMutex
	cfg *Config
}

func (p *Plugin) Configure(_ context.Context, req *configv1.ConfigureRequest) (*configv1.ConfigureResponse, error) {
	c := new(Config)
	if err := hcl.Decode(c, req.HclConfiguration); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "decode config: %v", err)
	}
	if c.DBPath == "" {
		return nil, status.Error(codes.InvalidArgument, "db_path is required")
	}
	p.mu.Lock()
	p.cfg = c
	p.mu.Unlock()
	return &configv1.ConfigureResponse{}, nil
}

// Attest returns no selectors for a pid that is not an msb VMM. It returns an
// error only when the pid looks like a VMM but a check fails.
func (p *Plugin) Attest(ctx context.Context, req *workloadattestorv1.AttestRequest) (*workloadattestorv1.AttestResponse, error) {
	p.mu.RLock()
	cfg := p.cfg
	p.mu.RUnlock()
	if cfg == nil {
		return nil, status.Error(codes.FailedPrecondition, "not configured")
	}
	pid := int(req.Pid)
	proc := "/proc/" + strconv.Itoa(pid)

	exe, err := os.Readlink(proc + "/exe")
	if err != nil || filepath.Base(exe) != "msb" {
		return &workloadattestorv1.AttestResponse{}, nil
	}
	raw, err := os.ReadFile(proc + "/cmdline")
	if err != nil {
		return nil, status.Errorf(codes.Internal, "read cmdline: %v", err)
	}
	args := strings.Split(strings.TrimRight(string(raw), "\x00"), "\x00")
	if len(args) < 2 || args[1] != "machine" {
		return &workloadattestorv1.AttestResponse{}, nil // msb, but not a VMM
	}
	name, id := flagValue(args, "--name"), flagValue(args, "--sandbox-id")
	if name == "" || id == "" {
		return nil, status.Error(codes.FailedPrecondition, "VMM command line has no --name or --sandbox-id")
	}

	startedAt, err := lookupRun(ctx, cfg.DBPath, id, name, pid)
	if err != nil {
		return nil, status.Errorf(codes.PermissionDenied, "run row check: %v", err)
	}
	procStart, err := procStartTime(pid)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "proc start time: %v", err)
	}
	if d := procStart.Sub(startedAt).Abs(); d > maxStartSkew {
		return nil, status.Errorf(codes.PermissionDenied, "start time differs by %s", d)
	}
	return &workloadattestorv1.AttestResponse{SelectorValues: []string{"name:" + name, "id:" + id}}, nil
}

func flagValue(args []string, flag string) string {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == flag {
			return args[i+1]
		}
	}
	return ""
}

func lookupRun(ctx context.Context, path, id, name string, pid int) (time.Time, error) {
	db, err := sql.Open("sqlite", "file:"+path+"?mode=ro")
	if err != nil {
		return time.Time{}, err
	}
	defer db.Close()
	var started string
	err = db.QueryRowContext(ctx,
		`SELECT r.started_at FROM run r JOIN sandbox s ON s.id = r.sandbox_id
		 WHERE s.id = ? AND s.name = ? AND r.pid = ? AND r.status = 'Running'`,
		id, name, pid).Scan(&started)
	if err != nil {
		return time.Time{}, fmt.Errorf("no running row for sandbox %s/%s pid %d: %w", name, id, pid, err)
	}
	t, err := time.Parse("2006-01-02 15:04:05.999999999", started)
	if err != nil {
		return time.Time{}, err
	}
	return t, nil
}

// procStartTime returns the start time of a pid in UTC (boot time + starttime ticks).
func procStartTime(pid int) (time.Time, error) {
	stat, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat")
	if err != nil {
		return time.Time{}, err
	}
	s := string(stat)
	fields := strings.Fields(s[strings.LastIndexByte(s, ')')+2:]) // fields after the comm
	ticks, err := strconv.ParseInt(fields[19], 10, 64)            // field 22 of stat
	if err != nil {
		return time.Time{}, err
	}
	sys, err := os.ReadFile("/proc/stat")
	if err != nil {
		return time.Time{}, err
	}
	var btime int64
	for _, l := range strings.Split(string(sys), "\n") {
		if strings.HasPrefix(l, "btime ") {
			btime, _ = strconv.ParseInt(strings.Fields(l)[1], 10, 64)
		}
	}
	const clkTck = 100 // shortcut: sysconf(_SC_CLK_TCK) is 100 on Linux x86_64
	return time.Unix(btime, 0).Add(time.Duration(ticks) * time.Second / clkTck).UTC(), nil
}

func main() {
	p := new(Plugin)
	pluginmain.Serve(
		workloadattestorv1.WorkloadAttestorPluginServer(p),
		configv1.ConfigServiceServer(p),
	)
}
```

</details>

### The delegate

The delegate sends one pid to `admin.sock` and prints what comes back. It never prints the private key. A real proxy needs more (see PR 4).

Save the source as `main.go` in a second empty folder. Build it with these commands:

```text
go mod init spike/delegate
go get github.com/spiffe/spire-api-sdk@v1.2.5-0.20260428072036-00f73a61093a google.golang.org/grpc@v1.84.0
go mod tidy
go build -o delegate .
```

<details>
<summary>delegate/main.go (58 lines)</summary>

```go
// Spike: delegate. It sends one pid to the admin socket of the SPIRE agent and
// prints what comes back. It never prints the private key.
package main

import (
	"context"
	"crypto/x509"
	"flag"
	"fmt"
	"os"
	"time"

	delegatedidentityv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/agent/delegatedidentity/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	sock := flag.String("socket", "", "admin socket path")
	pid := flag.Int("pid", 0, "pid to attest")
	flag.Parse()

	conn, err := grpc.NewClient("unix://"+*sock, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		fail(err)
	}
	defer conn.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	stream, err := delegatedidentityv1.NewDelegatedIdentityClient(conn).
		SubscribeToX509SVIDs(ctx, &delegatedidentityv1.SubscribeToX509SVIDsRequest{Pid: int32(*pid)})
	if err != nil {
		fail(err)
	}
	resp, err := stream.Recv()
	if err != nil {
		fail(err)
	}
	fmt.Printf("svids=%d\n", len(resp.X509Svids))
	for _, s := range resp.X509Svids {
		cert, err := x509.ParseCertificate(s.X509Svid.CertChain[0])
		if err != nil {
			fail(err)
		}
		key, err := x509.ParsePKCS8PrivateKey(s.X509SvidKey)
		if err != nil {
			fail(err)
		}
		fmt.Printf("spiffe_id=spiffe://%s%s\nnot_after=%s\nkey_parsed=%T\nuri_san=%v\n",
			s.X509Svid.Id.TrustDomain, s.X509Svid.Id.Path, cert.NotAfter.UTC().Format(time.RFC3339), key, cert.URIs)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "ERROR:", err)
	os.Exit(1)
}
```

</details>

### The configs

The server is a throwaway SPIRE server on localhost. It never touches the cluster.

<details>
<summary>spike-server.conf</summary>

```hcl
# Spike server. It is a throwaway SPIRE server on localhost with its own CA and a sqlite file.
# It never touches the cluster. Replace <RUN> and <DATA> with folders that you own.
server {
  bind_address = "127.0.0.1"
  bind_port    = "18081"
  socket_path  = "<RUN>/spike-spire/server.sock"
  trust_domain = "mcp.local"
  data_dir     = "<DATA>"
  log_level    = "INFO"
}

plugins {
  DataStore    "sql"        { plugin_data { database_type = "sqlite3"  connection_string = "<DATA>/ds.sqlite3" } }
  KeyManager   "memory"     { plugin_data {} }
  NodeAttestor "join_token" { plugin_data {} }
}
```

</details>

The agent joins that server with a join token.

<details>
<summary>spike-agent.conf</summary>

```hcl
# Spike agent. It joins a throwaway local server with a join token.
# Replace <RUN> with a folder under /run/user/<uid>, <SPIKE> with the folder of the built binaries, <HOME> with the home folder.
# The admin socket must be in a different folder from the Workload API socket. The agent refuses to start if both share a folder.
agent {
  data_dir             = "<RUN>/spike-spire/data"
  socket_path          = "<RUN>/spike-spire/agent.sock"
  admin_socket_path    = "<RUN>/spike-spire-admin/admin.sock"
  authorized_delegates = ["spiffe://mcp.local/spike/launcher"]
  trust_domain         = "mcp.local"
  server_address       = "127.0.0.1"
  server_port          = "18081"
  insecure_bootstrap   = true
  log_level            = "DEBUG"
}

plugins {
  NodeAttestor     "join_token" { plugin_data {} }
  KeyManager       "memory"     { plugin_data {} }
  WorkloadAttestor "unix"       { plugin_data { discover_workload_path = true } }
  WorkloadAttestor "msbvm" {
    plugin_cmd      = "<SPIKE>/plugin/msbvm"
    plugin_checksum = "<sha256sum of the msbvm binary>"
    plugin_data { db_path = "<HOME>/.microsandbox/db/msb.db" }
  }
}
```

</details>


## Rules for the session

- Never use `pkill -f` or `pgrep -f` with a pattern that also appears in your own command. It matches your shell.
- The permission check blocked two actions: a chained download, unpack and run, and `entry create` on the live server. Do each step on its own. Ask the user for the live server.
- Herdr was not running on 2026-11-07. `herdr worktree create` fails until the user starts `herdr`.

## Decisions of the user (do not reopen without a reason)

- The microVM is the workload. The key stays outside the guest.
- The SPIFFE ID has the node, the user and the VM.
- The SPIRE agent runs on the host, not in the VM.
- The user reads on a phone. Use short lists and narrow diagrams.
- Write all text in Simplified Technical English. Run `/asd-ste100` before you finish a change.

## Not checked

- The `x509pop` attestation of the host agent against the cluster server, and the alias parent.
- The proxy getting its own SVID through `agent.sock`.
- The use of the SVID for mTLS to the gateway. The spike only parsed it.
- A stop and start of the VM. I did not stop `sandbox-dev`, because that ends the user session.
- Collision of two agents with the same node certificate.
- `tpm_devid`, and whether the agent user can open the TPM.
- Whether agentgateway can read a URI SAN in a rule.
- A write on the cluster server. The permission check blocked it.

## Suggested skills

- `asd-ste100` before you finish any change.
- `tdd` for the plugin in PR 2.
- `pr` for the body of a PR.
- `gitops-knowledge` and the flux-schema-catalog for any Flux or Kubernetes manifest.
- `research` if a new question about SPIRE or `msb` comes up.
