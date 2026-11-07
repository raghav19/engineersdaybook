package attestor

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"

	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
)

// vmName is the VM that this test needs. It must run on the host.
const vmName = "sandbox-dev"

// TestRealVM attests the real VMM of the VM sandbox-dev against the real
// ~/.microsandbox/db/msb.db. Both are read-only. Run it with MSBVM_INTEGRATION=1.
func TestRealVM(t *testing.T) {
	if os.Getenv("MSBVM_INTEGRATION") != "1" {
		t.Skip("set MSBVM_INTEGRATION=1 to run this test against the real msb.db and the VM " + vmName)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	dbPath := filepath.Join(home, ".microsandbox", "db", "msb.db")
	pid := vmmPid(t, vmName)
	id := sandboxID(t, dbPath, vmName)

	p := New()
	hcl := fmt.Sprintf("db_path = %q", dbPath)
	if _, err := p.Configure(context.Background(), &configv1.ConfigureRequest{HclConfiguration: hcl}); err != nil {
		t.Fatalf("Configure() = %v", err)
	}
	resp, err := p.Attest(context.Background(), &workloadattestorv1.AttestRequest{Pid: int32(pid)})
	if err != nil {
		t.Fatalf("Attest(%d) = %v", pid, err)
	}
	want := []string{"name:" + vmName, "id:" + id}
	if !reflect.DeepEqual(resp.SelectorValues, want) {
		t.Errorf("selectors = %v, want %v", resp.SelectorValues, want)
	}
	t.Logf("pid %d gave the selectors %v", pid, resp.SelectorValues)
}

// vmmPid finds the pid of the process "msb machine --name <name>".
func vmmPid(t *testing.T, name string) int {
	t.Helper()
	out, err := exec.Command("ps", "-eo", "pid,args").Output()
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 5 || !strings.HasSuffix(fields[1], "msb") || fields[2] != "machine" {
			continue
		}
		for i := 3; i+1 < len(fields); i++ {
			if fields[i] == "--name" && fields[i+1] == name {
				pid, err := strconv.Atoi(fields[0])
				if err != nil {
					t.Fatal(err)
				}
				return pid
			}
		}
	}
	t.Fatalf("no process %q found with ps", "msb machine --name "+name)
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
