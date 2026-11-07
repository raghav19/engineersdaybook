// Command delegate asks the host SPIRE agent for the SVID of one microVM.
// It prints the SPIFFE ID, the expiry and the URI SAN. It never prints the key.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/delegate"
)

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	home, _ := os.UserHomeDir()
	fs := flag.NewFlagSet("delegate", flag.ContinueOnError)
	fs.SetOutput(stderr)
	vm := fs.String("vm", "", "name of the microVM (required)")
	socket := fs.String("socket", "", "admin socket of the host SPIRE agent (required)")
	db := fs.String("db", filepath.Join(home, ".microsandbox", "db", "msb.db"), "path of msb.db")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *vm == "" || *socket == "" {
		fmt.Fprintln(stderr, "delegate: -vm and -socket are required")
		return 2
	}

	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	svid, err := delegate.Fetch(ctx, delegate.Config{VM: *vm, Socket: *socket, DBPath: *db})
	if err != nil {
		fmt.Fprintf(stderr, "delegate: %v\n", err)
		return 1
	}
	fmt.Fprintf(stdout, "spiffe_id=%s\nnot_after=%s\n", svid.ID, svid.NotAfter.UTC().Format(time.RFC3339))
	for _, u := range svid.Chain[0].URIs {
		fmt.Fprintf(stdout, "uri_san=%s\n", u)
	}
	return 0
}
