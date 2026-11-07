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
func findPID(procRoot, vm string) (int, error) {
	entries, err := os.ReadDir(procRoot)
	if err != nil {
		return 0, err
	}
	var pids []int
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
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
