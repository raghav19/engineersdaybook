// Spike: WorkloadAttestor "msbvm". It maps a host pid to a microsandbox VM.
// Input is one pid. Output is the selectors name:<vm> and id:<sandbox-id>.
// Three checks must agree: the exe is msb, the command line names the VM,
// and the "run" row of msb.db has the same pid and start time.
package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/hashicorp/hcl"
	"github.com/spiffe/spire-plugin-sdk/pluginmain"
	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	_ "modernc.org/sqlite"
)

const maxStartSkew = 2 * time.Second

type Config struct {
	DBPath string `hcl:"db_path"`
}

type Plugin struct {
	workloadattestorv1.UnimplementedWorkloadAttestorServer
	configv1.UnimplementedConfigServer
	mu  sync.RWMutex
	cfg *Config
}

func (p *Plugin) Configure(_ context.Context, req *configv1.ConfigureRequest) (*configv1.ConfigureResponse, error) {
	c := new(Config)
	if err := hcl.Decode(c, req.HclConfiguration); err != nil {
		return nil, status.Errorf(codes.InvalidArgument, "decode config: %v", err)
	}
	if c.DBPath == "" {
		return nil, status.Error(codes.InvalidArgument, "db_path is required")
	}
	p.mu.Lock()
	p.cfg = c
	p.mu.Unlock()
	return &configv1.ConfigureResponse{}, nil
}

// Attest returns no selectors for a pid that is not an msb VMM. It returns an
// error only when the pid looks like a VMM but a check fails.
func (p *Plugin) Attest(ctx context.Context, req *workloadattestorv1.AttestRequest) (*workloadattestorv1.AttestResponse, error) {
	p.mu.RLock()
	cfg := p.cfg
	p.mu.RUnlock()
	if cfg == nil {
		return nil, status.Error(codes.FailedPrecondition, "not configured")
	}
	pid := int(req.Pid)
	proc := "/proc/" + strconv.Itoa(pid)

	exe, err := os.Readlink(proc + "/exe")
	if err != nil || filepath.Base(exe) != "msb" {
		return &workloadattestorv1.AttestResponse{}, nil
	}
	raw, err := os.ReadFile(proc + "/cmdline")
	if err != nil {
		return nil, status.Errorf(codes.Internal, "read cmdline: %v", err)
	}
	args := strings.Split(strings.TrimRight(string(raw), "\x00"), "\x00")
	if len(args) < 2 || args[1] != "machine" {
		return &workloadattestorv1.AttestResponse{}, nil // msb, but not a VMM
	}
	name, id := flagValue(args, "--name"), flagValue(args, "--sandbox-id")
	if name == "" || id == "" {
		return nil, status.Error(codes.FailedPrecondition, "VMM command line has no --name or --sandbox-id")
	}

	startedAt, err := lookupRun(ctx, cfg.DBPath, id, name, pid)
	if err != nil {
		return nil, status.Errorf(codes.PermissionDenied, "run row check: %v", err)
	}
	procStart, err := procStartTime(pid)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "proc start time: %v", err)
	}
	if d := procStart.Sub(startedAt).Abs(); d > maxStartSkew {
		return nil, status.Errorf(codes.PermissionDenied, "start time differs by %s", d)
	}
	return &workloadattestorv1.AttestResponse{SelectorValues: []string{"name:" + name, "id:" + id}}, nil
}

func flagValue(args []string, flag string) string {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == flag {
			return args[i+1]
		}
	}
	return ""
}

func lookupRun(ctx context.Context, path, id, name string, pid int) (time.Time, error) {
	db, err := sql.Open("sqlite", "file:"+path+"?mode=ro")
	if err != nil {
		return time.Time{}, err
	}
	defer db.Close()
	var started string
	err = db.QueryRowContext(ctx,
		`SELECT r.started_at FROM run r JOIN sandbox s ON s.id = r.sandbox_id
		 WHERE s.id = ? AND s.name = ? AND r.pid = ? AND r.status = 'Running'`,
		id, name, pid).Scan(&started)
	if err != nil {
		return time.Time{}, fmt.Errorf("no running row for sandbox %s/%s pid %d: %w", name, id, pid, err)
	}
	t, err := time.Parse("2006-01-02 15:04:05.999999999", started)
	if err != nil {
		return time.Time{}, err
	}
	return t, nil
}

// procStartTime returns the start time of a pid in UTC (boot time + starttime ticks).
func procStartTime(pid int) (time.Time, error) {
	stat, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat")
	if err != nil {
		return time.Time{}, err
	}
	s := string(stat)
	fields := strings.Fields(s[strings.LastIndexByte(s, ')')+2:]) // fields after the comm
	ticks, err := strconv.ParseInt(fields[19], 10, 64)            // field 22 of stat
	if err != nil {
		return time.Time{}, err
	}
	sys, err := os.ReadFile("/proc/stat")
	if err != nil {
		return time.Time{}, err
	}
	var btime int64
	for _, l := range strings.Split(string(sys), "\n") {
		if strings.HasPrefix(l, "btime ") {
			btime, _ = strconv.ParseInt(strings.Fields(l)[1], 10, 64)
		}
	}
	const clkTck = 100 // shortcut: sysconf(_SC_CLK_TCK) is 100 on Linux x86_64
	return time.Unix(btime, 0).Add(time.Duration(ticks) * time.Second / clkTck).UTC(), nil
}

func main() {
	p := new(Plugin)
	pluginmain.Serve(
		workloadattestorv1.WorkloadAttestorPluginServer(p),
		configv1.ConfigServiceServer(p),
	)
}
