# msbvm plugin

`msbvm` is a SPIRE workload attestor for the host agent. It turns the pid of a VMM into the name and the sandbox ID of a microVM. Read the [workload attestation guide](../docs/workload-attestation.md) for the design.

## Config

Add the plugin to the agent config:

```hcl
WorkloadAttestor "msbvm" {
  plugin_cmd      = "<path of the msbvm binary>"
  plugin_checksum = "<sha256 of the binary>"
  plugin_data { db_path = "<home>/.microsandbox/db/msb.db" }
}
```

You must set `db_path`. The plugin opens the file read-only and never writes to it.

At start, `Configure` checks the columns of the tables `sandbox` and `run`. If a column is missing, `Configure` fails and the message names msb 0.7.13.

## Selectors

For a good VMM, the plugin returns two selectors:

- `name:<vm>` is the name from `--name`.
- `id:<sandbox-id>` is the ID from `--sandbox-id`.

In the registration entry, the type of a selector is the plugin name: `msbvm:name:<vm>`.

## The three checks

The pid comes from the delegate. Three checks must agree:

1. The exe of the process is `msb`, and its first argument is `machine`.
2. The command line has `--name` and `--sandbox-id` with values.
3. `msb.db` has a `run` row with the same sandbox ID and name, the same pid and the status `Running`. The `started_at` of the row is within 2 seconds of the start time in `/proc`.

| Case | Result |
|---|---|
| The pid is not `msb`, or is `msb` but not `machine` | Empty response, no selectors |
| `msb machine` without name or sandbox ID | `FailedPrecondition` |
| No matching `run` row, or the start times differ | `PermissionDenied` |
| All checks pass | The selectors above |

A fake `msb` can copy the exe name and the command line. It cannot make a `run` row. The agent turns an empty response into zero SVIDs, so the delegate must treat zero SVIDs as a failure.

## Packages

- `internal/vmm` parses the exe and the command line.
- `internal/proc` reads `/proc`. The root of `/proc` is an argument, so tests use a fake tree.
- `internal/msbdb` reads `msb.db` and checks its schema.
- `internal/msbtest` makes fake databases for tests.
- `internal/attestor` has the plugin. `main.go` only starts it.

The clock tick of `/proc` is a constant of 100. A `TODO:` in `internal/proc/proc.go` names the check for it.

## Run the tests

You need Go 1.27.3 and [`just`](https://just.systems).

```text
just test
```

The integration test reads the real `~/.microsandbox/db/msb.db` and the real VMM of the running VM `sandbox-dev`. It only reads. It skips unless `MSBVM_INTEGRATION=1`.

```text
just integration
```

## Build

```text
just build
```

This builds `build/msbvm` and prints its sha256. The `build/` folder is not in git. Copy the checksum into `plugin_checksum` of the agent config. Build again after each change, because the checksum changes.

## The msb version risk

The tables `sandbox` and `run` are internal to msb. Their columns can change in a new version. We tested the plugin with msb 0.7.13 only. The schema check at start makes a change visible, but it cannot find a change of meaning. Test again after each upgrade of msb. If a column of the query is gone, `Configure` fails and the agent does not load the plugin.
