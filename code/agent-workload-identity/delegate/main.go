// Command delegate asks the host SPIRE agent for the SVID of one microVM.
// It prints the SPIFFE ID and the expiry. It never prints the key.
//
// This file is the entry point. The command does three steps:
//  1. It reads the flags.
//  2. It calls findPID (vmm.go) to find the pid of the VMM of the VM.
//  3. It calls fetchSVID (agent.go) to get the SVID of that pid.
//
// The delegate only guesses the pid. The plugin msbvm in the SPIRE agent checks
// the pid against msb.db. A wrong pid gets zero SVIDs.
//
// The exit code is 0 for success, 1 for a failure, and 2 for wrong flags.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"time"
)

// main runs the command with the real /proc and the real output streams.
func main() {
	os.Exit(run(context.Background(), os.Args[1:], "/proc", os.Stdout, os.Stderr))
}

// run does the work of main. It takes the root of /proc and the output
// streams as arguments, so that the tests can use a fake /proc and read the
// output. It returns the exit code.
func run(ctx context.Context, args []string, procRoot string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("delegate", flag.ContinueOnError)
	fs.SetOutput(stderr)
	vm := fs.String("vm", "", "name of the microVM (required)")
	id := fs.String("id", "", "SPIFFE ID that the SVID of the VM must have (required)")
	socket := fs.String("socket", "", "admin socket of the host SPIRE agent (required)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	// The command needs all three flags. Without them, the delegate cannot know
	// which VM to ask for, which ID to expect, or where the agent is.
	if *vm == "" || *id == "" || *socket == "" {
		fmt.Fprintln(stderr, "delegate: -vm, -id and -socket are required")
		return 2
	}

	// The whole command must end within 15 seconds.
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	// Step 1: find the pid of the VMM.
	pid, err := findPID(procRoot, *vm)
	if err != nil {
		fmt.Fprintf(stderr, "delegate: %v\n", err)
		return 1
	}
	// Step 2: ask the agent for the SVID of that pid. The result is the SVID
	// with the expected ID, or an error.
	svid, err := fetchSVID(ctx, *socket, pid, *id)
	if err != nil {
		fmt.Fprintf(stderr, "delegate: %v\n", err)
		return 1
	}
	// Step 3: print the ID and the expiry. The key stays in memory. It is never
	// printed.
	fmt.Fprintf(stdout, "spiffe_id=%s\nnot_after=%s\n", svid.id, svid.notAfter.Format(time.RFC3339))
	return 0
}
