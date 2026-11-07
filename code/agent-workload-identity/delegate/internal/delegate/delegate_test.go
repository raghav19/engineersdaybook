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

const (
	spiffeID = "spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/vm-a"
	otherID  = "spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/vm-b"
)

func kill(cmd *exec.Cmd) {
	_ = cmd.Process.Kill()
	_ = cmd.Wait()
}

func mustURL(s string) *url.URL {
	u, err := url.Parse(s)
	if err != nil {
		panic(err)
	}
	return u
}

func TestFetch(t *testing.T) {
	notAfter := time.Now().Add(time.Hour).Truncate(time.Second)
	id := mustURL(spiffeID)

	tests := []struct {
		name string
		// setup returns the rows of msb.db and the hooks of the test.
		setup     func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks)
		wantErr   []string // every text must be in the error
		wantIs    error
		wantCalls int
	}{
		{
			name: "SVID comes back",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				fake.Response, _, _ = testutil.NewSVID(t, id, notAfter)
				return []testutil.Run{{Sandbox: "vm-a", PID: testutil.StartProcess(t, "vm-a").Process.Pid, Status: "Running"}}, hooks{}
			},
			wantCalls: 1,
		},
		{
			name: "the expected SVID is the second in the answer",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				fake.Response = testutil.NewSVIDs(t, []*url.URL{mustURL(otherID), id}, notAfter)
				return []testutil.Run{{Sandbox: "vm-a", PID: testutil.StartProcess(t, "vm-a").Process.Pid, Status: "Running"}}, hooks{}
			},
			wantCalls: 1,
		},
		{
			name: "the agent returns the SVID of another VM",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				fake.Response, _, _ = testutil.NewSVID(t, mustURL(otherID), notAfter)
				return []testutil.Run{{Sandbox: "vm-a", PID: testutil.StartProcess(t, "vm-a").Process.Pid, Status: "Running"}}, hooks{}
			},
			wantIs:    ErrIDMismatch,
			wantErr:   []string{spiffeID, otherID},
			wantCalls: 1,
		},
		{
			name: "agent returns zero SVIDs",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				fake.Response = &delegatedidentityv1.SubscribeToX509SVIDsResponse{}
				return []testutil.Run{{Sandbox: "vm-a", PID: testutil.StartProcess(t, "vm-a").Process.Pid, Status: "Running"}}, hooks{}
			},
			wantIs:    agent.ErrRefused,
			wantCalls: 1,
		},
		{
			name: "no running row",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				return []testutil.Run{{Sandbox: "vm-a", PID: 1, Status: "Stopped"}}, hooks{}
			},
			wantErr: []string{"no running row"},
		},
		{
			name: "wrong command line",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				return []testutil.Run{{Sandbox: "vm-a", PID: testutil.StartProcess(t, "vm-other").Process.Pid, Status: "Running"}}, hooks{}
			},
			wantErr: []string{"command line"},
		},
		{
			name: "process is gone and its pid is in the row",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				cmd := testutil.StartProcess(t, "vm-a")
				kill(cmd)
				return []testutil.Run{{Sandbox: "vm-a", PID: cmd.Process.Pid, Status: "Running"}}, hooks{}
			},
			wantErr: []string{"pid"},
		},
		{
			name: "process exits after the pidfd is open",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				cmd := testutil.StartProcess(t, "vm-a")
				return []testutil.Run{{Sandbox: "vm-a", PID: cmd.Process.Pid, Status: "Running"}}, hooks{afterOpen: func() { kill(cmd) }}
			},
			wantErr: []string{"exited"},
		},
		{
			name: "process exits during the call, so the SVID is not used",
			setup: func(t *testing.T, fake *testutil.FakeAgent) ([]testutil.Run, hooks) {
				fake.Response, _, _ = testutil.NewSVID(t, id, notAfter)
				cmd := testutil.StartProcess(t, "vm-a")
				return []testutil.Run{{Sandbox: "vm-a", PID: cmd.Process.Pid, Status: "Running"}}, hooks{afterCall: func() { kill(cmd) }}
			},
			wantErr:   []string{"exited during the call"},
			wantCalls: 1,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			fake := testutil.StartFakeAgent(t)
			runs, h := tc.setup(t, fake)
			cfg := Config{VM: "vm-a", ID: spiffeID, Socket: fake.Socket, DBPath: testutil.NewMsbDB(t, runs)}

			got, err := fetch(t.Context(), cfg, h)

			if n := len(fake.Calls()); n != tc.wantCalls {
				t.Errorf("calls to the agent = %d, want %d", n, tc.wantCalls)
			}
			if tc.wantIs != nil && !errors.Is(err, tc.wantIs) {
				t.Fatalf("error = %v, want %v", err, tc.wantIs)
			}
			if len(tc.wantErr) > 0 || tc.wantIs != nil {
				if err == nil {
					t.Fatal("want an error")
				}
				if got != nil {
					t.Errorf("an SVID came back together with the error: %v", got)
				}
				for _, w := range tc.wantErr {
					if !strings.Contains(err.Error(), w) {
						t.Errorf("error = %v, want text %q", err, w)
					}
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got.ID != spiffeID || !got.NotAfter.Equal(notAfter) {
				t.Errorf("got %v", got)
			}
		})
	}
}
