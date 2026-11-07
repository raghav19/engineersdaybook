// Command delegate asks the host SPIRE agent for the SVID of one microVM.
// It prints the SPIFFE ID and the expiry. It never prints the key.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"time"
)

func main() {
	os.Exit(run(context.Background(), os.Args[1:], "/proc", os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, procRoot string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("delegate", flag.ContinueOnError)
	fs.SetOutput(stderr)
	vm := fs.String("vm", "", "name of the microVM (required)")
	id := fs.String("id", "", "SPIFFE ID that the SVID of the VM must have (required)")
	socket := fs.String("socket", "", "admin socket of the host SPIRE agent (required)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *vm == "" || *id == "" || *socket == "" {
		fmt.Fprintln(stderr, "delegate: -vm, -id and -socket are required")
		return 2
	}

	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	pid, err := findPID(procRoot, *vm)
	if err != nil {
		fmt.Fprintf(stderr, "delegate: %v\n", err)
		return 1
	}
	svid, err := fetchSVID(ctx, *socket, pid, *id)
	if err != nil {
		fmt.Fprintf(stderr, "delegate: %v\n", err)
		return 1
	}
	fmt.Fprintf(stdout, "spiffe_id=%s\nnot_after=%s\n", svid.id, svid.notAfter.Format(time.RFC3339))
	return 0
}
