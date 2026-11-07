// Package vmm reads the command line of a process and tells whether it is the
// VMM of a microsandbox VM. The VMM is the process "msb machine".
package vmm

import (
	"path/filepath"
	"strings"
)

// Kind is the result of the parse. The plugin treats each kind in its own way.
type Kind int

const (
	// NotMsb means that the exe of the process is not msb.
	NotMsb Kind = iota
	// NotMachine means that the process is msb, but its first argument is not "machine".
	NotMachine
	// Incomplete means that the process is "msb machine", but --name or --sandbox-id has no value.
	Incomplete
	// Machine means that the process is the VMM of a VM. Name and ID are set.
	Machine
)

// VMM is the result of Parse. Name and ID are set only for Kind Machine.
type VMM struct {
	Kind Kind
	Name string
	ID   string
}

// Parse takes the target of /proc/<pid>/exe and the raw content of
// /proc/<pid>/cmdline (arguments that end with a NUL byte).
func Parse(exe string, cmdline []byte) VMM {
	if filepath.Base(exe) != "msb" {
		return VMM{Kind: NotMsb}
	}
	args := strings.Split(strings.TrimRight(string(cmdline), "\x00"), "\x00")
	if len(args) < 2 || args[1] != "machine" {
		return VMM{Kind: NotMachine}
	}
	name, id := flagValue(args, "--name"), flagValue(args, "--sandbox-id")
	if name == "" || id == "" {
		return VMM{Kind: Incomplete}
	}
	return VMM{Kind: Machine, Name: name, ID: id}
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
