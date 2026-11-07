package main

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"testing"

	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
)

// vmName is the VM that this test needs. The test must run on the host.
const vmName = "sandbox-dev"

// TestRealVM attests the real VMM of the VM sandbox-dev against the real
// ~/.microsandbox/db/msb.db. It only reads. Run it with MSBVM_INTEGRATION=1.
func TestRealVM(t *testing.T) {
	if os.Getenv("MSBVM_INTEGRATION") != "1" {
		t.Skip("set MSBVM_INTEGRATION=1 to run this test against the real msb.db and the VM " + vmName)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(home, ".microsandbox", "db", "msb.db")
	pid := realVMMPid(t, vmName)
	wantID := sandboxID(t, dbPath, vmName)

	p := New()
	if _, err := p.Configure(t.Context(), &configv1.ConfigureRequest{HclConfiguration: fmt.Sprintf("db_path = %q", dbPath)}); err != nil {
		t.Fatalf("Configure() = %v", err)
	}
	resp, err := p.Attest(t.Context(), &workloadattestorv1.AttestRequest{Pid: int32(pid)})
	if err != nil {
		t.Fatalf("Attest(%d) = %v", pid, err)
	}
	want := []string{"name:" + vmName, "id:" + wantID}
	if !reflect.DeepEqual(resp.SelectorValues, want) {
		t.Errorf("selectors = %v, want %v", resp.SelectorValues, want)
	}
	t.Logf("pid %d gave the selectors %v", pid, resp.SelectorValues)
}

// realVMMPid scans the real /proc for the process "msb machine --name <name>".
func realVMMPid(t *testing.T, name string) int {
	t.Helper()
	entries, err := os.ReadDir("/proc")
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		exe, err := os.Readlink(filepath.Join("/proc", e.Name(), "exe"))
		if err != nil || filepath.Base(exe) != "msb" {
			continue
		}
		cmdline, err := os.ReadFile(filepath.Join("/proc", e.Name(), "cmdline"))
		if err != nil {
			continue
		}
		args := strings.Split(string(cmdline), "\x00")
		if i := slices.Index(args, "--name"); i >= 0 && i+1 < len(args) && args[i+1] == name {
			return pid
		}
	}
	t.Fatalf("no VMM of the VM %q found in /proc", name)
	return 0
}

// sandboxID reads the sandbox ID from the real database. It is an independent
// source: the plugin reads the ID from the command line of the VMM.
func sandboxID(t *testing.T, dbPath, name string) string {
	t.Helper()
	db, err := sql.Open("sqlite", "file:"+dbPath+"?mode=ro")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var id int
	if err := db.QueryRow(`SELECT id FROM sandbox WHERE name = ?`, name).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return strconv.Itoa(id)
}
