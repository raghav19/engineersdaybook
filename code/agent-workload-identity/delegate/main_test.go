package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	_, socket := startFakeAgent(t, answer(vmA), nil)
	proc := fakeProc(t, map[string][]string{"100": {"/opt/msb", "machine", "--name", "vm-a", "--sandbox-id", "7"}})

	tests := []struct {
		name     string
		args     []string
		wantCode int
		wantOut  []string
		wantErr  string
	}{
		{
			name:     "prints the ID and the expiry",
			args:     []string{"-vm", "vm-a", "-id", vmA, "-socket", socket},
			wantCode: 0,
			wantOut:  []string{"spiffe_id=" + vmA, "not_after=2030-01-02T03:04:05Z"},
		},
		{name: "no VM name", args: []string{"-id", vmA, "-socket", socket}, wantCode: 2, wantErr: "-vm"},
		{name: "no ID", args: []string{"-vm", "vm-a", "-socket", socket}, wantCode: 2, wantErr: "-id"},
		{name: "no socket", args: []string{"-vm", "vm-a", "-id", vmA}, wantCode: 2, wantErr: "-socket"},
		{name: "unknown VM", args: []string{"-vm", "vm-x", "-id", vmA, "-socket", socket}, wantCode: 1, wantErr: "no VMM"},
		{name: "the agent returns another ID", args: []string{"-vm", "vm-a", "-id", vmB, "-socket", socket}, wantCode: 1, wantErr: "expected ID"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var out, errOut bytes.Buffer
			code := run(t.Context(), tc.args, proc, &out, &errOut)
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
			if strings.Contains(out.String()+errOut.String(), "secret") {
				t.Error("output shows the key")
			}
		})
	}
}
