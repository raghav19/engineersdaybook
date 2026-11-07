// File vmm.go finds the VMM of a microVM.
//
// The VMM is the host process that runs one microVM. In msb it is the process
// "msb machine --name <vm> --sandbox-id <id> ...". Each running VM has one VMM.
// The pid of the VMM is the input of the Delegated Identity API.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// findPID returns the pid of the VMM of the VM: the process "msb machine
// --name <vm>". It scans procRoot (/proc). It only guesses. The plugin msbvm
// checks the pid against msb.db when the agent attests it. A wrong pid gets
// zero SVIDs.
//
// The function fails in two cases. It finds no VMM of the VM, or it finds more
// than one. It does not choose between two VMMs, because a wrong choice would
// ask the agent about the wrong process.
func findPID(procRoot, vm string) (int, error) {
	entries, err := os.ReadDir(procRoot)
	if err != nil {
		return 0, err
	}
	var pids []int
	for _, e := range entries {
		// In /proc, each process has a folder. The name of the folder is its pid.
		// Other entries, such as "self" and "cpuinfo", are not processes.
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		// cmdline holds the arguments of the process, separated by NUL bytes.
		raw, err := os.ReadFile(filepath.Join(procRoot, e.Name(), "cmdline"))
		if err != nil {
			continue // the process ended, or we may not read it
		}
		if isVMM(strings.Split(strings.TrimRight(string(raw), "\x00"), "\x00"), vm) {
			pids = append(pids, pid)
		}
	}
	switch len(pids) {
	case 0:
		return 0, fmt.Errorf("no VMM of the VM %q found", vm)
	case 1:
		return pids[0], nil
	}
	return 0, fmt.Errorf("more than one VMM of the VM %q found: pids %v", vm, pids)
}

// isVMM reports whether args are the command line of "msb machine --name <vm>".
// Example of a match for the VM "sandbox-dev":
//
//	/opt/msb machine --name sandbox-dev --sandbox-id 184 ...
//
// The first argument must end with "msb". The second must be "machine". The
// value after "--name" must be the name of the VM.
func isVMM(args []string, vm string) bool {
	if len(args) < 2 || filepath.Base(args[0]) != "msb" || args[1] != "machine" {
		return false
	}
	for i := 2; i+1 < len(args); i++ {
		if args[i] == "--name" {
			return args[i+1] == vm
		}
	}
	return false
}
