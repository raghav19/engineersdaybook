package vmm

import "testing"

func TestParse(t *testing.T) {
	tests := []struct {
		name    string
		exe     string
		cmdline string
		want    VMM
	}{
		{
			name:    "a VMM",
			exe:     "/home/u/.microsandbox/bin/msb",
			cmdline: "msb\x00machine\x00--name\x00sandbox-dev\x00--sandbox-id\x00184\x00--other\x00x\x00",
			want:    VMM{Kind: Machine, Name: "sandbox-dev", ID: "184"},
		},
		{
			name:    "flags in another order",
			exe:     "/usr/bin/msb",
			cmdline: "msb\x00machine\x00--sandbox-id\x007\x00--name\x00vm1\x00",
			want:    VMM{Kind: Machine, Name: "vm1", ID: "7"},
		},
		{
			name:    "exe is not msb",
			exe:     "/usr/bin/sleep",
			cmdline: "msb\x00machine\x00--name\x00a\x00--sandbox-id\x001\x00",
			want:    VMM{Kind: NotMsb},
		},
		{
			name:    "exe name only ends with msb",
			exe:     "/usr/bin/notmsb",
			cmdline: "msb\x00machine\x00--name\x00a\x00--sandbox-id\x001\x00",
			want:    VMM{Kind: NotMsb},
		},
		{
			name:    "msb with another subcommand",
			exe:     "/usr/bin/msb",
			cmdline: "msb\x00ls\x00--name\x00a\x00--sandbox-id\x001\x00",
			want:    VMM{Kind: NotMachine},
		},
		{
			name:    "msb with no argument",
			exe:     "/usr/bin/msb",
			cmdline: "msb\x00",
			want:    VMM{Kind: NotMachine},
		},
		{
			name:    "empty command line",
			exe:     "/usr/bin/msb",
			cmdline: "",
			want:    VMM{Kind: NotMachine},
		},
		{
			name:    "machine without name",
			exe:     "/usr/bin/msb",
			cmdline: "msb\x00machine\x00--sandbox-id\x001\x00",
			want:    VMM{Kind: Incomplete},
		},
		{
			name:    "machine without sandbox ID",
			exe:     "/usr/bin/msb",
			cmdline: "msb\x00machine\x00--name\x00a\x00",
			want:    VMM{Kind: Incomplete},
		},
		{
			name:    "flag at the end has no value",
			exe:     "/usr/bin/msb",
			cmdline: "msb\x00machine\x00--sandbox-id\x001\x00--name\x00",
			want:    VMM{Kind: Incomplete},
		},
		{
			name:    "empty value",
			exe:     "/usr/bin/msb",
			cmdline: "msb\x00machine\x00--name\x00\x00--sandbox-id\x001\x00",
			want:    VMM{Kind: Incomplete},
		},
		{
			name:    "value is the next flag",
			exe:     "/usr/bin/msb",
			cmdline: "msb\x00machine\x00--name\x00--sandbox-id\x001\x00",
			want:    VMM{Kind: Incomplete},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := Parse(tc.exe, []byte(tc.cmdline)); got != tc.want {
				t.Errorf("Parse() = %+v, want %+v", got, tc.want)
			}
		})
	}
}
