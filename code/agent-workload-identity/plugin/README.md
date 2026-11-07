# msbvm plugin

`msbvm` is a SPIRE workload attestor for microsandbox (`msb`). The SPIRE agent gives it the pid of a process. It returns two selectors: `name:<vm>` and `id:<sandbox-id>`. A registration entry matches these selectors. For example, the VM entry matches `msbvm:name:sandbox-dev`.

Read the [workload attestation guide](../docs/workload-attestation.md) for the design.

## What it does

`Attest` does two checks on the pid:

1. The exe of the process is `msb`. The plugin reads the kernel link `/proc/<pid>/exe`. A process cannot change this link. This check protects against a stale row in `msb.db` whose pid another process now uses.
2. `msb.db` has a `run` row with this pid and the status `Running`. Only `msb` writes this row. The row gives the name and the sandbox ID of the VM.

The result:

- Both checks pass: it returns `name:<vm>` and `id:<sandbox-id>`.
- A check fails, or the process ended: it returns no selectors and no error. Most processes on the host are like this.
- `msb.db` cannot be read: it returns the error `Internal`.

In every refusal, the agent returns zero SVIDs to the delegate.

The plugin is the one part that verifies the pid. The delegate only guesses the pid and checks the ID of the answer. The delegate finds a pid from a name. The plugin finds a name from a pid. The database has both.

## What it does not check

- **The command line.** The row has the name and the ID, so the plugin does not parse the command line.
- **The start time.** The plugin does not compare the start time of the process with the start time in `msb.db`. That check needed about 150 lines of code and tests, and it was not deterministic. A stale `Running` row plus a reused pid is the only case that it would catch. The exe check and the check of the ID in the delegate cover most of that case.

## Configuration

The block of the plugin in the agent config:

```text
WorkloadAttestor "msbvm" {
    plugin_cmd      = "<path of the msbvm binary>"
    plugin_checksum = "<sha256 of the binary>"
    plugin_data { db_path = "<home>/.microsandbox/db/msb.db" }
}
```

`Configure` opens `msb.db` read-only. It runs the real query once on an empty result. If a table or a column is missing, the agent fails at start with a message that names the tested `msb` version. This is better than a wrong answer later.

## Build, test and run

Use `just` in this folder:

```text
just test         run the unit tests
just build        build build/msbvm and print its sha256 (the value for plugin_checksum)
just integration  attest the real VMM of the VM sandbox-dev against the real msb.db
```

The unit tests use no real `msb` and no network. They write a fake `/proc` and a fake `msb.db` in a temporary folder. The integration test only reads. It needs a running VM `sandbox-dev`, and it skips unless `MSBVM_INTEGRATION=1`.

## Tested msb version

We tested the plugin with `msb` 0.7.13. The tables `sandbox` and `run` are internal to `msb`, and a new version can change them. Run `just integration` after each `msb` update.

## Files

- `main.go`: starts the plugin.
- `plugin.go`: `Configure` and `Attest`.
- `msbdb.go`: the query on `msb.db`.
