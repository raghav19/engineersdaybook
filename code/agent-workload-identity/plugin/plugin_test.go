package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"

	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	_ "modernc.org/sqlite"
)

// run is one row of the fake table "run".
type run struct {
	sandboxID int
	name      string
	pid       int
	status    string
}

// newMsbDB writes a fake msb.db with the tables "sandbox" and "run" and the
// columns of msb 0.7.13 that the plugin reads.
func newMsbDB(t *testing.T, runs []run) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "msb.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, q := range []string{
		`CREATE TABLE sandbox (id integer PRIMARY KEY, name text NOT NULL)`,
		`CREATE TABLE run (id integer PRIMARY KEY AUTOINCREMENT, sandbox_id integer NOT NULL, pid integer, status text NOT NULL)`,
	} {
		if _, err := db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	for _, r := range runs {
		if _, err := db.Exec(`INSERT OR IGNORE INTO sandbox (id, name) VALUES (?, ?)`, r.sandboxID, r.name); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO run (sandbox_id, pid, status) VALUES (?, ?, ?)`, r.sandboxID, r.pid, r.status); err != nil {
			t.Fatal(err)
		}
	}
	return path
}

// fakeProc writes a fake /proc with one process. exe is the target of the
// link /proc/<pid>/exe. An empty exe means that the process has no exe link.
func fakeProc(t *testing.T, pid int, exe string, args ...string) string {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, strconv.Itoa(pid))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if exe != "" {
		if err := os.Symlink(exe, filepath.Join(dir, "exe")); err != nil {
			t.Fatal(err)
		}
	}
	cmdline := ""
	for _, a := range args {
		cmdline += a + "\x00"
	}
	if err := os.WriteFile(filepath.Join(dir, "cmdline"), []byte(cmdline), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func configured(t *testing.T, procRoot, dbPath string) *Plugin {
	t.Helper()
	p := &Plugin{procRoot: procRoot}
	if _, err := p.Configure(t.Context(), &configv1.ConfigureRequest{HclConfiguration: fmt.Sprintf("db_path = %q", dbPath)}); err != nil {
		t.Fatalf("Configure() = %v", err)
	}
	return p
}

func TestAttest(t *testing.T) {
	const pid = 4242
	vmm := []string{"/opt/msb", "machine", "--name", "vm-a", "--sandbox-id", "184"}
	goodRun := run{184, "vm-a", pid, "Running"}

	tests := []struct {
		name      string
		exe       string
		args      []string
		runs      []run
		want      []string   // selectors
		wantError codes.Code // codes.OK means no error
	}{
		{name: "a VMM with a running row", exe: "/opt/msb", args: vmm, runs: []run{goodRun}, want: []string{"name:vm-a", "id:184"}},
		{name: "the process is gone", exe: "", args: vmm, runs: []run{goodRun}},
		{name: "exe is not msb", exe: "/bin/sleep", args: vmm, runs: []run{goodRun}},
		{name: "msb with another subcommand", exe: "/opt/msb", args: []string{"/opt/msb", "run", "--name", "vm-a"}, runs: []run{goodRun}},
		{name: "machine without a sandbox ID", exe: "/opt/msb", args: []string{"/opt/msb", "machine", "--name", "vm-a"}, runs: []run{goodRun}},
		{name: "no row at all", exe: "/opt/msb", args: vmm, wantError: codes.PermissionDenied},
		{name: "row has another pid", exe: "/opt/msb", args: vmm, runs: []run{{184, "vm-a", pid + 1, "Running"}}, wantError: codes.PermissionDenied},
		{name: "row has another sandbox ID", exe: "/opt/msb", args: vmm, runs: []run{{185, "vm-a", pid, "Running"}}, wantError: codes.PermissionDenied},
		{name: "row has another VM name", exe: "/opt/msb", args: vmm, runs: []run{{184, "vm-b", pid, "Running"}}, wantError: codes.PermissionDenied},
		{name: "row is stopped", exe: "/opt/msb", args: vmm, runs: []run{{184, "vm-a", pid, "Stopped"}}, wantError: codes.PermissionDenied},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			p := configured(t, fakeProc(t, pid, tc.exe, tc.args...), newMsbDB(t, tc.runs))

			resp, err := p.Attest(t.Context(), &workloadattestorv1.AttestRequest{Pid: pid})

			if got := status.Code(err); got != tc.wantError {
				t.Fatalf("Attest() error = %v (code %v), want code %v", err, got, tc.wantError)
			}
			if err == nil && !reflect.DeepEqual(resp.SelectorValues, tc.want) {
				t.Errorf("selectors = %v, want %v", resp.SelectorValues, tc.want)
			}
		})
	}
}

func TestAttestNotConfigured(t *testing.T) {
	p := &Plugin{procRoot: t.TempDir()}
	_, err := p.Attest(t.Context(), &workloadattestorv1.AttestRequest{Pid: 1})
	if status.Code(err) != codes.FailedPrecondition {
		t.Fatalf("error = %v, want code FailedPrecondition", err)
	}
}

func TestConfigure(t *testing.T) {
	good := newMsbDB(t, nil)
	oldSchema := filepath.Join(t.TempDir(), "old.db")
	db, err := sql.Open("sqlite", oldSchema)
	if err != nil {
		t.Fatal(err)
	}
	// A "run" table without the column "pid": msb has changed its tables.
	for _, q := range []string{
		`CREATE TABLE sandbox (id integer PRIMARY KEY, name text)`,
		`CREATE TABLE run (id integer PRIMARY KEY, sandbox_id integer, status text)`,
	} {
		if _, err := db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	db.Close()

	tests := []struct {
		name     string
		hcl      string
		wantCode codes.Code
		wantText string // text of the message of the error
	}{
		{"good database", fmt.Sprintf("db_path = %q", good), codes.OK, ""},
		{"no db_path", ``, codes.InvalidArgument, "db_path"},
		{"not HCL", `db_path = "unclosed`, codes.InvalidArgument, "decode"},
		{"database does not exist", `db_path = "/nonexistent/msb.db"`, codes.FailedPrecondition, "msb.db"},
		{"tables have changed", fmt.Sprintf("db_path = %q", oldSchema), codes.FailedPrecondition, "0.7.13"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			p := &Plugin{procRoot: t.TempDir()}
			_, err := p.Configure(context.Background(), &configv1.ConfigureRequest{HclConfiguration: tc.hcl})
			if got := status.Code(err); got != tc.wantCode {
				t.Fatalf("Configure() error = %v (code %v), want code %v", err, got, tc.wantCode)
			}
			if tc.wantText != "" && !strings.Contains(err.Error(), tc.wantText) {
				t.Errorf("error = %v, want text %q", err, tc.wantText)
			}
		})
	}
}
