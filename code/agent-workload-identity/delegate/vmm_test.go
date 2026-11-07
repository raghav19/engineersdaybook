package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeProc writes a fake /proc. Each entry maps a pid folder name to the
// arguments of the process.
func fakeProc(t *testing.T, procs map[string][]string) string {
	t.Helper()
	root := t.TempDir()
	for pid, args := range procs {
		dir := filepath.Join(root, pid)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		cmdline := strings.Join(args, "\x00") + "\x00"
		if err := os.WriteFile(filepath.Join(dir, "cmdline"), []byte(cmdline), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestFindPID(t *testing.T) {
	vmmOf := func(name string) []string {
		return []string{"/opt/msb", "machine", "--name", name, "--sandbox-id", "7"}
	}
	tests := []struct {
		name    string
		procs   map[string][]string
		want    int
		wantErr string
	}{
		{"the VMM of the VM", map[string][]string{"100": vmmOf("vm-a")}, 100, ""},
		{"VMMs of other VMs are ignored", map[string][]string{"100": vmmOf("vm-b"), "200": vmmOf("vm-a")}, 200, ""},
		{"a process that is not msb is ignored", map[string][]string{"100": {"/bin/sleep", "machine", "--name", "vm-a"}}, 0, "no VMM"},
		{"msb with another subcommand is ignored", map[string][]string{"100": {"/opt/msb", "run", "--name", "vm-a"}}, 0, "no VMM"},
		{"no VMM at all", map[string][]string{"100": {"/bin/sleep", "1"}}, 0, "no VMM"},
		{"two VMMs of the VM are ambiguous", map[string][]string{"100": vmmOf("vm-a"), "200": vmmOf("vm-a")}, 0, "more than one"},
		{"folders that are not pids are ignored", map[string][]string{"self": vmmOf("vm-a"), "300": vmmOf("vm-a")}, 300, ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := findPID(fakeProc(t, tc.procs), "vm-a")
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("error = %v, want text %q", err, tc.wantErr)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("pid = %d, error = %v, want pid %d", got, err, tc.want)
			}
		})
	}
}
