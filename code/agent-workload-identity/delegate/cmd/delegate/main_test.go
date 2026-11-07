package main

import (
	"bytes"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/testutil"
)

const spiffeID = "spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/vm-a"

func TestRun(t *testing.T) {
	id, _ := url.Parse(spiffeID)
	notAfter := time.Date(2030, 1, 2, 3, 4, 5, 0, time.UTC)
	fake := testutil.StartFakeAgent(t)
	var keyDER []byte
	fake.Response, _, keyDER = testutil.NewSVID(t, id, notAfter)
	proc := testutil.StartProcess(t, "vm-a")
	db := testutil.NewMsbDB(t, []testutil.Run{{Sandbox: "vm-a", PID: proc.Process.Pid, Status: "Running"}})

	tests := []struct {
		name     string
		args     []string
		wantCode int
		wantOut  []string
		wantErr  string
	}{
		{
			name:     "prints ID, not_after and URI SAN",
			args:     []string{"-vm", "vm-a", "-socket", fake.Socket, "-db", db},
			wantCode: 0,
			wantOut: []string{
				"spiffe_id=" + spiffeID,
				"not_after=2030-01-02T03:04:05Z",
				"uri_san=" + spiffeID,
			},
		},
		{name: "no VM name", args: []string{"-socket", fake.Socket, "-db", db}, wantCode: 2, wantErr: "-vm"},
		{name: "no socket", args: []string{"-vm", "vm-a", "-db", db}, wantCode: 2, wantErr: "-socket"},
		{name: "unknown VM", args: []string{"-vm", "vm-x", "-socket", fake.Socket, "-db", db}, wantCode: 1, wantErr: "no running row"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var out, errOut bytes.Buffer
			code := run(t.Context(), tc.args, &out, &errOut)
			if code != tc.wantCode {
				t.Fatalf("exit code = %d, want %d (stderr: %s)", code, tc.wantCode, errOut.String())
			}
			for _, w := range tc.wantOut {
				if !strings.Contains(out.String(), w+"\n") {
					t.Errorf("stdout lacks line %q: %q", w, out.String())
				}
			}
			if tc.wantErr != "" && !strings.Contains(errOut.String(), tc.wantErr) {
				t.Errorf("stderr = %q, want text %q", errOut.String(), tc.wantErr)
			}
			for _, s := range []string{out.String(), errOut.String()} {
				if strings.Contains(s, string(keyDER)) || strings.Contains(s, "PRIVATE KEY") {
					t.Error("output shows the private key")
				}
			}
		})
	}
}
