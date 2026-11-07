package pidfd_test

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/pidfd"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/testutil"
)

func TestAlive(t *testing.T) {
	tests := []struct {
		name    string
		stop    func(t *testing.T, cmd *exec.Cmd)
		wantErr bool
	}{
		{"process runs", func(*testing.T, *exec.Cmd) {}, false},
		{"process killed and reaped", func(_ *testing.T, cmd *exec.Cmd) {
			_ = cmd.Process.Kill()
			_ = cmd.Wait()
		}, true},
		{"process killed, zombie not reaped", func(t *testing.T, cmd *exec.Cmd) {
			_ = cmd.Process.Kill()
			waitZombie(t, cmd.Process.Pid)
		}, true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cmd := testutil.StartProcess(t, "vm-a")
			fd, err := pidfd.Open(cmd.Process.Pid)
			if err != nil {
				t.Fatal(err)
			}
			defer fd.Close()
			tc.stop(t, cmd)
			if err := fd.Alive(); (err != nil) != tc.wantErr {
				t.Fatalf("Alive() error = %v, want error: %v", err, tc.wantErr)
			}
		})
	}
}

func TestOpenGonePID(t *testing.T) {
	cmd := testutil.StartProcess(t, "vm-a")
	_ = cmd.Process.Kill()
	_ = cmd.Wait()
	if fd, err := pidfd.Open(cmd.Process.Pid); err == nil {
		fd.Close()
		t.Fatal("want an error for a pid that is gone")
	}
}

// waitZombie blocks until the process has exited but the parent has not reaped it.
func waitZombie(t *testing.T, pid int) {
	t.Helper()
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(5 * time.Millisecond) {
		stat, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/stat")
		if err == nil && strings.HasPrefix(string(stat[strings.LastIndexByte(string(stat), ')')+2:]), "Z") {
			return
		}
	}
	t.Fatal("process did not become a zombie")
}
