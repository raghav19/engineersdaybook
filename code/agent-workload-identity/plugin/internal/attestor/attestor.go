// Package attestor is the SPIRE workload attestor "msbvm". It maps the pid of
// a VMM to a microsandbox VM. Three checks must agree: the exe is msb, the
// command line names the VM, and the "run" row of msb.db has the same pid and
// start time.
package attestor

import (
	"context"
	"sync"
	"time"

	"github.com/hashicorp/hcl"
	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/plugin/internal/msbdb"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/plugin/internal/proc"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/plugin/internal/vmm"
)

// maxStartSkew is the largest difference between the start time in msb.db and
// the start time in /proc. The spike measured 5 ms on a real VM.
const maxStartSkew = 2 * time.Second

// Config is the HCL configuration of the plugin.
type Config struct {
	DBPath string `hcl:"db_path"`
}

// Plugin implements the WorkloadAttestor and Config services.
type Plugin struct {
	workloadattestorv1.UnimplementedWorkloadAttestorServer
	configv1.UnimplementedConfigServer

	procRoot string // the root of /proc. Tests change it.

	mu  sync.RWMutex
	cfg *Config
}

// New returns a plugin that reads the real /proc.
func New() *Plugin {
	return &Plugin{procRoot: "/proc"}
}

// Configure reads db_path and checks the schema of msb.db.
func (p *Plugin) Configure(ctx context.Context, req *configv1.ConfigureRequest) (*configv1.ConfigureResponse, error) {
	c := new(Config)
	if err := hcl.Decode(c, req.HclConfiguration); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "decode config: %v", err)
	}
	if c.DBPath == "" {
		return nil, status.Error(codes.InvalidArgument, "db_path is required")
	}
	db, err := msbdb.Open(c.DBPath)
	if err != nil {
		return nil, status.Errorf(codes.FailedPrecondition, "open %s: %v", c.DBPath, err)
	}
	defer db.Close()
	if err := db.CheckSchema(ctx); err != nil {
		return nil, status.Errorf(codes.FailedPrecondition, "check the schema of %s: %v", c.DBPath, err)
	}
	p.mu.Lock()
	p.cfg = c
	p.mu.Unlock()
	return &configv1.ConfigureResponse{}, nil
}

// Attest returns no selectors for a pid that is not a VMM. It returns an error
// when the pid looks like a VMM but a check fails.
func (p *Plugin) Attest(ctx context.Context, req *workloadattestorv1.AttestRequest) (*workloadattestorv1.AttestResponse, error) {
	p.mu.RLock()
	cfg := p.cfg
	p.mu.RUnlock()
	if cfg == nil {
		return nil, status.Error(codes.FailedPrecondition, "not configured")
	}
	pid := int(req.Pid)

	exe, err := proc.Exe(p.procRoot, pid)
	if err != nil {
		return &workloadattestorv1.AttestResponse{}, nil // the process is gone, or we cannot read it
	}
	cmdline, err := proc.Cmdline(p.procRoot, pid)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "read cmdline: %v", err)
	}
	v := vmm.Parse(exe, cmdline)
	switch v.Kind {
	case vmm.NotMsb, vmm.NotMachine:
		return &workloadattestorv1.AttestResponse{}, nil
	case vmm.Incomplete:
		return nil, status.Error(codes.FailedPrecondition, "VMM command line has no --name or --sandbox-id")
	}

	if err := p.checkRun(ctx, cfg.DBPath, v, pid); err != nil {
		return nil, err
	}
	return &workloadattestorv1.AttestResponse{SelectorValues: []string{"name:" + v.Name, "id:" + v.ID}}, nil
}

// checkRun checks the "run" row of msb.db against the start time in /proc.
func (p *Plugin) checkRun(ctx context.Context, dbPath string, v vmm.VMM, pid int) error {
	db, err := msbdb.Open(dbPath)
	if err != nil {
		return status.Errorf(codes.PermissionDenied, "run row check: %v", err)
	}
	defer db.Close()
	startedAt, err := db.RunStartedAt(ctx, v.ID, v.Name, pid)
	if err != nil {
		return status.Errorf(codes.PermissionDenied, "run row check: %v", err)
	}
	procStart, err := proc.StartTime(p.procRoot, pid)
	if err != nil {
		return status.Errorf(codes.Internal, "proc start time: %v", err)
	}
	if d := procStart.Sub(startedAt).Abs(); d > maxStartSkew {
		return status.Errorf(codes.PermissionDenied, "run row check: start time differs by %s", d)
	}
	return nil
}
