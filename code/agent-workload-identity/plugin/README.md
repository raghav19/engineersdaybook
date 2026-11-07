# msbvm plugin

`msbvm` is a SPIRE workload attestor. It turns the pid of a VMM into the name and the sandbox ID of a microVM. Read the [workload attestation guide](../docs/workload-attestation.md) for the design.

**Status.** This folder has the helper packages only. The plugin itself (the `Attest` method and `main.go`) comes in the next PR.

## Packages

- `internal/vmm` reads the exe and the command line of a process. It tells apart four results: not `msb`, `msb` but not `machine`, `msb machine` without `--name` or `--sandbox-id`, and a good VMM.
- `internal/proc` reads the start time of a pid from `/proc/<pid>/stat` and `/proc/stat`. The root of `/proc` is an argument, so tests use a fake tree.

The clock tick is a constant of 100. A `TODO:` in `internal/proc/proc.go` names the check for it.

## Run the tests

```text
go test ./...
```

You need Go 1.27.3. The tests use no network and no `msb`. One test reads the real `/proc` of the host. It skips if `/proc` does not exist.

## Tested msb version

The tests assume the command line of `msb` 0.7.13: `msb machine --name <vm> --sandbox-id <id> ...`. Another version of `msb` can change this command line.
