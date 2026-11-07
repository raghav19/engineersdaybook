package attestor

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/spiffe/spire-plugin-sdk/pluginsdk"
	"github.com/spiffe/spire-plugin-sdk/plugintest"
	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/plugin/internal/msbtest"
)

const (
	vmPid = 4242
	// The fake /proc has btime 1000000000 and start ticks 12345. So the process
	// started at 1000000123.45 seconds.
	btime      = 1000000000
	startTicks = 12345
)

var procStart = time.Unix(btime+123, 450000000).UTC()

// fakeVMM is a fake process in the fake /proc.
type fakeVMM struct {
	exe     string // target of the exe link. "" means no link, as for a pid that does not exist.
	cmdline string
	stat    bool
}

func goodVMM() fakeVMM {
	return fakeVMM{
		exe:     "/home/u/.microsandbox/bin/msb",
		cmdline: "msb\x00machine\x00--name\x00sandbox-dev\x00--sandbox-id\x00184\x00",
		stat:    true,
	}
}

func fakeProc(t *testing.T, pid int, v fakeVMM) string {
	t.Helper()
	root := t.TempDir()
	write := func(path, content string) {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(root, "stat"), fmt.Sprintf("cpu 1 2 3\nbtime %d\n", btime))
	dir := filepath.Join(root, fmt.Sprint(pid))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if v.exe != "" {
		if err := os.Symlink(v.exe, filepath.Join(dir, "exe")); err != nil {
			t.Fatal(err)
		}
	}
	if v.cmdline != "" {
		write(filepath.Join(dir, "cmdline"), v.cmdline)
	}
	if v.stat {
		write(filepath.Join(dir, "stat"), fmt.Sprintf("%d (msb) S 1 1 1 0 -1 0 0 0 0 0 1 2 0 0 20 0 1 0 %d 1000 200\n", pid, startTicks))
	}
	return root
}

// dbWithRun makes a fake msb.db with the sandbox 184/sandbox-dev and one run.
func dbWithRun(t *testing.T, pid int, status string, startedAt time.Time) string {
	return msbtest.Create(t, msbtest.Schema,
		`INSERT INTO sandbox (id, name, status) VALUES (184, 'sandbox-dev', 'Running')`,
		fmt.Sprintf(`INSERT INTO run (sandbox_id, pid, status, started_at) VALUES (184, %d, '%s', '%s')`,
			pid, status, startedAt.Format("2006-01-02 15:04:05.000000000")),
	)
}

// serve runs the plugin behind the SDK test server and returns its two clients.
func serve(t *testing.T, p *Plugin) (workloadattestorv1.WorkloadAttestorClient, configv1.ConfigClient) {
	t.Helper()
	wa := new(workloadattestorv1.WorkloadAttestorPluginClient)
	cfg := new(configv1.ConfigServiceClient)
	plugintest.ServeInBackground(t, plugintest.Config{
		PluginServer:   workloadattestorv1.WorkloadAttestorPluginServer(p),
		PluginClient:   wa,
		ServiceServers: []pluginsdk.ServiceServer{configv1.ConfigServiceServer(p)},
		ServiceClients: []pluginsdk.ServiceClient{cfg},
	})
	return wa, cfg
}

func configure(t *testing.T, c configv1.ConfigClient, dbPath string) {
	t.Helper()
	_, err := c.Configure(context.Background(), &configv1.ConfigureRequest{HclConfiguration: fmt.Sprintf("db_path = %q", dbPath)})
	if err != nil {
		t.Fatalf("Configure() = %v", err)
	}
}

func TestAttest(t *testing.T) {
	tests := []struct {
		name     string
		vmm      fakeVMM
		dbPid    int
		dbStatus string
		dbStart  time.Time
		wantCode codes.Code
		want     []string // selectors, only for codes.OK
	}{
		{
			name: "a good VMM", vmm: goodVMM(), dbPid: vmPid, dbStatus: "Running", dbStart: procStart,
			want: []string{"name:sandbox-dev", "id:184"},
		},
		{
			name: "start times differ by 1.5 seconds", vmm: goodVMM(), dbPid: vmPid, dbStatus: "Running",
			dbStart: procStart.Add(-1500 * time.Millisecond),
			want:    []string{"name:sandbox-dev", "id:184"},
		},
		{
			name: "start times differ by 3 seconds", vmm: goodVMM(), dbPid: vmPid, dbStatus: "Running",
			dbStart: procStart.Add(3 * time.Second), wantCode: codes.PermissionDenied,
		},
		{
			name: "no run row with this pid", vmm: goodVMM(), dbPid: vmPid + 1, dbStatus: "Running",
			dbStart: procStart, wantCode: codes.PermissionDenied,
		},
		{
			name: "run row is not Running", vmm: goodVMM(), dbPid: vmPid, dbStatus: "Terminated",
			dbStart: procStart, wantCode: codes.PermissionDenied,
		},
		{
			name: "exe is not msb", dbPid: vmPid, dbStatus: "Running", dbStart: procStart,
			vmm: fakeVMM{exe: "/usr/bin/sleep", cmdline: goodVMM().cmdline, stat: true},
		},
		{
			name: "pid does not exist", dbPid: vmPid, dbStatus: "Running", dbStart: procStart,
			vmm: fakeVMM{},
		},
		{
			name: "msb but not machine", dbPid: vmPid, dbStatus: "Running", dbStart: procStart,
			vmm: fakeVMM{exe: goodVMM().exe, cmdline: "msb\x00ls\x00", stat: true},
		},
		{
			name: "machine without sandbox ID", dbPid: vmPid, dbStatus: "Running", dbStart: procStart,
			vmm:      fakeVMM{exe: goodVMM().exe, cmdline: "msb\x00machine\x00--name\x00sandbox-dev\x00", stat: true},
			wantCode: codes.FailedPrecondition,
		},
		{
			name: "no cmdline file", dbPid: vmPid, dbStatus: "Running", dbStart: procStart,
			vmm:      fakeVMM{exe: goodVMM().exe, stat: true},
			wantCode: codes.Internal,
		},
		{
			name: "no stat file", dbPid: vmPid, dbStatus: "Running", dbStart: procStart,
			vmm:      fakeVMM{exe: goodVMM().exe, cmdline: goodVMM().cmdline},
			wantCode: codes.Internal,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			p := New()
			p.procRoot = fakeProc(t, vmPid, tc.vmm)
			wa, cfg := serve(t, p)
			configure(t, cfg, dbWithRun(t, tc.dbPid, tc.dbStatus, tc.dbStart))

			resp, err := wa.Attest(context.Background(), &workloadattestorv1.AttestRequest{Pid: vmPid})
			if got := status.Code(err); got != tc.wantCode {
				t.Fatalf("Attest() code = %v (%v), want %v", got, err, tc.wantCode)
			}
			if err == nil && !reflect.DeepEqual(resp.SelectorValues, tc.want) {
				t.Errorf("selectors = %v, want %v", resp.SelectorValues, tc.want)
			}
		})
	}
}

func TestAttestBeforeConfigure(t *testing.T) {
	wa, _ := serve(t, New())
	_, err := wa.Attest(context.Background(), &workloadattestorv1.AttestRequest{Pid: vmPid})
	if got := status.Code(err); got != codes.FailedPrecondition {
		t.Fatalf("Attest() code = %v (%v), want FailedPrecondition", got, err)
	}
}

func TestConfigure(t *testing.T) {
	goodDB := msbtest.Create(t, msbtest.Schema)
	oldDB := msbtest.Create(t,
		`CREATE TABLE sandbox (id INTEGER, name TEXT)`,
		`CREATE TABLE run (id INTEGER, sandbox_id INTEGER, pid INTEGER, status TEXT)`,
	)
	tests := []struct {
		name     string
		hcl      string
		wantCode codes.Code
		wantText string
	}{
		{name: "good config", hcl: fmt.Sprintf("db_path = %q", goodDB)},
		{name: "no db_path", hcl: ``, wantCode: codes.InvalidArgument, wantText: "db_path"},
		{name: "bad HCL", hcl: `db_path = `, wantCode: codes.InvalidArgument},
		{name: "database does not exist", hcl: `db_path = "/nonexistent/msb.db"`, wantCode: codes.FailedPrecondition, wantText: "0.7.13"},
		{name: "schema lacks a column", hcl: fmt.Sprintf("db_path = %q", oldDB), wantCode: codes.FailedPrecondition, wantText: "started_at"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, cfg := serve(t, New())
			_, err := cfg.Configure(context.Background(), &configv1.ConfigureRequest{HclConfiguration: tc.hcl})
			if got := status.Code(err); got != tc.wantCode {
				t.Fatalf("Configure() code = %v (%v), want %v", got, err, tc.wantCode)
			}
			if tc.wantText != "" && !strings.Contains(err.Error(), tc.wantText) {
				t.Errorf("error %q does not contain %q", err, tc.wantText)
			}
		})
	}
}
