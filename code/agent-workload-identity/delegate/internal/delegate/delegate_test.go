package delegate

import (
	"errors"
	"net/url"
	"os/exec"
	"strings"
	"testing"
	"time"

	delegatedidentityv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/agent/delegatedidentity/v1"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/agent"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/testutil"
)

const spiffeID = "spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/vm-a"

func kill(cmd *exec.Cmd) {
	_ = cmd.Process.Kill()
	_ = cmd.Wait()
}

func TestFetch(t *testing.T) {
	id, _ := url.Parse(spiffeID)
	notAfter := time.Now().Add(time.Hour).Truncate(time.Second)

	tests := []struct {
		name string
		// setup returns the rows of msb.db and the hook that runs after the pidfd is open.
		setup     func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, func())
		wantErr   string
		wantIs    error
		wantCalls int
	}{
		{
			name: "SVID comes back",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, func()) {
				fake.Response, _, _ = testutil.NewSVID(t, id, notAfter)
				return []testutil.Run{{Sandbox: "vm-a", PID: testutil.StartProcess(t, "vm-a").Process.Pid, Status: "Running"}}, nil
			},
			wantCalls: 1,
		},
		{
			name: "agent returns zero SVIDs",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, func()) {
				fake.Response = &delegatedidentityv1.SubscribeToX509SVIDsResponse{}
				return []testutil.Run{{Sandbox: "vm-a", PID: testutil.StartProcess(t, "vm-a").Process.Pid, Status: "Running"}}, nil
			},
			wantIs:    agent.ErrRefused,
			wantCalls: 1,
		},
		{
			name: "no running row",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, func()) {
				return []testutil.Run{{Sandbox: "vm-a", PID: 1, Status: "Stopped"}}, nil
			},
			wantErr: "no running row",
		},
		{
			name: "wrong command line",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, func()) {
				return []testutil.Run{{Sandbox: "vm-a", PID: testutil.StartProcess(t, "vm-other").Process.Pid, Status: "Running"}}, nil
			},
			wantErr: "command line",
		},
		{
			name: "process is gone and its pid is in the row",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, func()) {
				cmd := testutil.StartProcess(t, "vm-a")
				kill(cmd)
				return []testutil.Run{{Sandbox: "vm-a", PID: cmd.Process.Pid, Status: "Running"}}, nil
			},
			wantErr: "pid",
		},
		{
			name: "process exits after the pidfd is open",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, func()) {
				cmd := testutil.StartProcess(t, "vm-a")
				return []testutil.Run{{Sandbox: "vm-a", PID: cmd.Process.Pid, Status: "Running"}}, func() { kill(cmd) }
			},
			wantErr: "exited",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			fake := testutil.StartFakeAgent(t)
			runs, afterOpen := tc.setup(t, fake)
			cfg := Config{VM: "vm-a", Socket: fake.Socket, DBPath: testutil.NewMsbDB(t, runs)}

			got, err := fetch(t.Context(), cfg, afterOpen)

			if n := len(fake.Calls()); n != tc.wantCalls {
				t.Errorf("calls to the agent = %d, want %d", n, tc.wantCalls)
			}
			switch {
			case tc.wantIs != nil:
				if !errors.Is(err, tc.wantIs) {
					t.Fatalf("error = %v, want %v", err, tc.wantIs)
				}
			case tc.wantErr != "":
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("error = %v, want text %q", err, tc.wantErr)
				}
			default:
				if err != nil {
					t.Fatal(err)
				}
				if got.ID != spiffeID || !got.NotAfter.Equal(notAfter) {
					t.Errorf("got %v", got)
				}
			}
		})
	}
}
