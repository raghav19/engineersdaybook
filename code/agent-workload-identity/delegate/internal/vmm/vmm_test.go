package vmm_test

import (
	"strings"
	"testing"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/testutil"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/vmm"
)

func TestFindPID(t *testing.T) {
	proc := testutil.StartProcess(t, "vm-a")
	pid := proc.Process.Pid

	tests := []struct {
		name    string
		runs    []testutil.Run
		vm      string
		wantPID int
		wantErr string
	}{
		{
			name:    "running row of the VM",
			runs:    []testutil.Run{{Sandbox: "vm-a", PID: pid, Status: "Running"}},
			vm:      "vm-a",
			wantPID: pid,
		},
		{
			name:    "old stopped row is ignored",
			runs:    []testutil.Run{{Sandbox: "vm-a", PID: 1, Status: "Stopped"}, {Sandbox: "vm-a", PID: pid, Status: "Running"}},
			vm:      "vm-a",
			wantPID: pid,
		},
		{
			name:    "row of another VM is ignored",
			runs:    []testutil.Run{{Sandbox: "vm-b", PID: 2, Status: "Running"}, {Sandbox: "vm-a", PID: pid, Status: "Running"}},
			vm:      "vm-a",
			wantPID: pid,
		},
		{
			name:    "no running row",
			runs:    []testutil.Run{{Sandbox: "vm-a", PID: pid, Status: "Stopped"}},
			vm:      "vm-a",
			wantErr: "no running row",
		},
		{
			name:    "unknown VM",
			runs:    []testutil.Run{{Sandbox: "vm-b", PID: 2, Status: "Running"}},
			vm:      "vm-a",
			wantErr: "no running row",
		},
		{
			name:    "running row with no pid",
			runs:    []testutil.Run{{Sandbox: "vm-a", PID: 0, Status: "Running"}},
			vm:      "vm-a",
			wantErr: "no running row",
		},
		{
			name:    "command line has another VM name",
			runs:    []testutil.Run{{Sandbox: "vm-b", PID: pid, Status: "Running"}},
			vm:      "vm-b",
			wantErr: "command line",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			db := testutil.NewMsbDB(t, tc.runs)
			got, err := vmm.FindPID(t.Context(), db, tc.vm)
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("error = %v, want text %q", err, tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got != tc.wantPID {
				t.Fatalf("pid = %d, want %d", got, tc.wantPID)
			}
		})
	}
}

func TestFindPIDMissingDB(t *testing.T) {
	_, err := vmm.FindPID(t.Context(), t.TempDir()+"/none.db", "vm-a")
	if err == nil {
		t.Fatal("want an error for a missing database")
	}
}
