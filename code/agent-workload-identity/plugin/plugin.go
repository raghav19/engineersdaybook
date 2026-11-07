// File plugin.go is the plugin itself. It has the two calls that the SPIRE
// agent makes: Configure (once, at start) and Attest (for each pid).
package main

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"sync"

	"github.com/hashicorp/hcl"
	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Config is the configuration of the plugin. The agent config sets it in the
// block plugin_data of the plugin:
//
//	WorkloadAttestor "msbvm" {
//	    plugin_cmd = "<path of the msbvm binary>"
//	    plugin_checksum = "<sha256 of the binary>"
//	    plugin_data { db_path = "<home>/.microsandbox/db/msb.db" }
//	}
type Config struct {
	DBPath string `hcl:"db_path"`
}

// Plugin implements the WorkloadAttestor service and the Config service of
// the SPIRE plugin SDK.
type Plugin struct {
	workloadattestorv1.UnimplementedWorkloadAttestorServer
	configv1.UnimplementedConfigServer

	procRoot string // the folder /proc. The tests use a fake one.

	mu     sync.RWMutex // the agent can call Configure while Attest runs
	dbPath string       // from the configuration
}

// New returns a plugin that reads the real /proc.
func New() *Plugin {
	return &Plugin{procRoot: "/proc"}
}

// Configure reads the path of msb.db. It also checks that msb.db has the
// tables and columns that the plugin needs. The tables are internal to msb, so
// a new version of msb can change them. If it did, the agent fails at start.
// This is better than a wrong answer later.
func (p *Plugin) Configure(ctx context.Context, req *configv1.ConfigureRequest) (*configv1.ConfigureResponse, error) {
	var c Config
	if err := hcl.Decode(&c, req.HclConfiguration); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "decode the configuration: %v", err)
	}
	if c.DBPath == "" {
		return nil, status.Error(codes.InvalidArgument, "db_path is required")
	}
	if err := checkTables(ctx, c.DBPath); err != nil {
		return nil, status.Errorf(codes.FailedPrecondition, "read %s (this plugin was tested with msb %s only): %v", c.DBPath, testedMsbVersion, err)
	}
	p.mu.Lock()
	p.dbPath = c.DBPath
	p.mu.Unlock()
	return &configv1.ConfigureResponse{}, nil
}

// Attest turns a pid into selectors. It does two checks:
//
//  1. The exe of the process is msb. The kernel link /proc/<pid>/exe tells the
//     real program. A process cannot change it. This check protects against a
//     stale row in msb.db whose pid another process now uses.
//  2. msb.db has a running row for the pid. The row gives the name and the
//     sandbox ID of the VM.
//
// If a check fails, Attest returns no selectors and no error. Most processes on
// the host are like this. The agent calls all its attestors for each pid. The
// agent then returns zero SVIDs to the delegate.
func (p *Plugin) Attest(ctx context.Context, req *workloadattestorv1.AttestRequest) (*workloadattestorv1.AttestResponse, error) {
	p.mu.RLock()
	dbPath := p.dbPath
	p.mu.RUnlock()
	if dbPath == "" {
		return nil, status.Error(codes.FailedPrecondition, "the plugin is not configured")
	}

	// If the read fails, for example because the process has ended, exe is
	// empty, and an empty exe is not msb.
	exe, _ := os.Readlink(filepath.Join(p.procRoot, strconv.Itoa(int(req.Pid)), "exe"))
	if filepath.Base(exe) != "msb" {
		return &workloadattestorv1.AttestResponse{}, nil
	}

	name, id, found, err := lookup(ctx, dbPath, int(req.Pid))
	if err != nil {
		return nil, status.Errorf(codes.Internal, "read msb.db: %v", err)
	}
	if !found {
		return &workloadattestorv1.AttestResponse{}, nil
	}
	return &workloadattestorv1.AttestResponse{SelectorValues: []string{"name:" + name, "id:" + id}}, nil
}
