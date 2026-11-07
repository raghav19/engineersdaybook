// File vmm.go reads the exe and the command line of a process and tells whether
// the process is the VMM of a microVM.
//
// The VMM is the host process that runs one microVM. In msb it looks like this:
//
//	exe:     <path>/msb
//	cmdline: <path>/msb machine --name sandbox-dev --sandbox-id 184 --vcpus 2 ...
package main

import (
	"path/filepath"
	"strings"
)

// parseVMM takes the target of /proc/<pid>/exe and the raw content of
// /proc/<pid>/cmdline. The kernel separates the arguments in cmdline with NUL
// bytes. parseVMM returns the name and the sandbox ID of the VM, and ok=true,
// if the process is a VMM.
//
// The exe comes from the kernel link /proc/<pid>/exe. A process cannot change
// it. The first argument can say anything, so the code does not use it.
//
// A process that is msb but has no name or no ID is not a VMM. Its answer is
// the same as for any other process: no selectors.
func parseVMM(exe string, cmdline []byte) (name, id string, ok bool) {
	if filepath.Base(exe) != "msb" {
		return "", "", false
	}
	args := strings.Split(strings.TrimRight(string(cmdline), "\x00"), "\x00")
	if len(args) < 2 || args[1] != "machine" {
		return "", "", false
	}
	name, id = flagValue(args, "--name"), flagValue(args, "--sandbox-id")
	if name == "" || id == "" {
		return "", "", false
	}
	return name, id, true
}

// flagValue returns the argument after flag. It returns "" if there is none,
// or if the next argument is another flag.
func flagValue(args []string, flag string) string {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == flag {
			if strings.HasPrefix(args[i+1], "--") {
				return ""
			}
			return args[i+1]
		}
	}
	return ""
}
