package main

import "testing"

func TestParseVMM(t *testing.T) {
	tests := []struct {
		name     string
		exe      string
		cmdline  string // arguments separated by NUL bytes, as in /proc
		wantName string
		wantID   string
		wantOK   bool
	}{
		{"a VMM", "/opt/msb", "/opt/msb\x00machine\x00--name\x00vm-a\x00--sandbox-id\x00184\x00--vcpus\x002\x00", "vm-a", "184", true},
		{"flags in another order", "/opt/msb", "/opt/msb\x00machine\x00--sandbox-id\x00184\x00--name\x00vm-a\x00", "vm-a", "184", true},
		{"exe is not msb", "/bin/sleep", "sleep\x00machine\x00--name\x00vm-a\x00--sandbox-id\x001\x00", "", "", false},
		{"exe name only ends with msb", "/opt/xmsb", "/opt/xmsb\x00machine\x00--name\x00vm-a\x00--sandbox-id\x001\x00", "", "", false},
		{"msb with another subcommand", "/opt/msb", "/opt/msb\x00run\x00--name\x00vm-a\x00--sandbox-id\x001\x00", "", "", false},
		{"msb with no argument", "/opt/msb", "/opt/msb\x00", "", "", false},
		{"empty command line", "/opt/msb", "", "", "", false},
		{"machine without name", "/opt/msb", "/opt/msb\x00machine\x00--sandbox-id\x00184\x00", "", "", false},
		{"machine without sandbox ID", "/opt/msb", "/opt/msb\x00machine\x00--name\x00vm-a\x00", "", "", false},
		{"flag at the end has no value", "/opt/msb", "/opt/msb\x00machine\x00--sandbox-id\x001\x00--name\x00", "", "", false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			name, id, ok := parseVMM(tc.exe, []byte(tc.cmdline))
			// The name and the ID are valid only when ok is true.
			if ok != tc.wantOK || (ok && (name != tc.wantName || id != tc.wantID)) {
				t.Errorf("parseVMM() = %q, %q, %v; want %q, %q, %v", name, id, ok, tc.wantName, tc.wantID, tc.wantOK)
			}
		})
	}
}
