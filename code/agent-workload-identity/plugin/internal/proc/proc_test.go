package proc

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// statLine builds a /proc/<pid>/stat line. After the comm, field 3 is the
// state. The start time is field 22, so 18 fields sit between them.
func statLine(pid int, comm string, startTicks string) string {
	return fmt.Sprintf("%d (%s) S 1 %d %d 0 -1 4194560 100 0 0 0 1 2 0 0 20 0 1 0 %s 1000 200 18446744073709551615 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0\n",
		pid, comm, pid, pid, startTicks)
}

// fakeProc writes a fake /proc tree. A nil stat or a nil pidStat leaves the file out.
func fakeProc(t *testing.T, pid int, sysStat, pidStat *string) string {
	t.Helper()
	root := t.TempDir()
	if sysStat != nil {
		if err := os.WriteFile(filepath.Join(root, "stat"), []byte(*sysStat), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if pidStat != nil {
		dir := filepath.Join(root, fmt.Sprint(pid))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "stat"), []byte(*pidStat), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func ptr(s string) *string { return &s }

func TestStartTime(t *testing.T) {
	sys := "cpu  1 2 3 4\nbtime 1000000000\nprocesses 99\n"
	tests := []struct {
		name    string
		sysStat *string
		pidStat *string
		want    time.Time
		wantErr bool
	}{
		{
			name:    "boot time plus ticks",
			sysStat: ptr(sys),
			pidStat: ptr(statLine(42, "msb", "12345")),
			want:    time.Unix(1000000123, 450000000).UTC(),
		},
		{
			name:    "comm with spaces and a closing parenthesis",
			sysStat: ptr(sys),
			pidStat: ptr(statLine(42, "evil) S 1 2 3 (x", "12345")),
			want:    time.Unix(1000000123, 450000000).UTC(),
		},
		{
			name:    "process started at boot",
			sysStat: ptr(sys),
			pidStat: ptr(statLine(42, "msb", "0")),
			want:    time.Unix(1000000000, 0).UTC(),
		},
		{name: "no stat file for the pid", sysStat: ptr(sys), wantErr: true},
		{name: "no /proc/stat", pidStat: ptr(statLine(42, "msb", "1")), wantErr: true},
		{name: "no btime line", sysStat: ptr("cpu 1 2 3\n"), pidStat: ptr(statLine(42, "msb", "1")), wantErr: true},
		{name: "btime is not a number", sysStat: ptr("btime x\n"), pidStat: ptr(statLine(42, "msb", "1")), wantErr: true},
		{name: "start ticks is not a number", sysStat: ptr(sys), pidStat: ptr(statLine(42, "msb", "abc")), wantErr: true},
		{name: "no closing parenthesis", sysStat: ptr(sys), pidStat: ptr("42 msb S 1 2\n"), wantErr: true},
		{name: "too few fields", sysStat: ptr(sys), pidStat: ptr("42 (msb) S 1 2\n"), wantErr: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			root := fakeProc(t, 42, tc.sysStat, tc.pidStat)
			got, err := StartTime(root, 42)
			if (err != nil) != tc.wantErr {
				t.Fatalf("StartTime() error = %v, wantErr %v", err, tc.wantErr)
			}
			if !tc.wantErr && !got.Equal(tc.want) {
				t.Errorf("StartTime() = %v, want %v", got, tc.want)
			}
		})
	}
}

// The real /proc checks the clock tick constant: with a wrong value, the start
// time of this test process would be far from now.
func TestStartTimeRealProc(t *testing.T) {
	if _, err := os.Stat("/proc/self/stat"); err != nil {
		t.Skip("no /proc on this system")
	}
	got, err := StartTime("/proc", os.Getpid())
	if err != nil {
		t.Fatal(err)
	}
	if d := time.Since(got); d < -2*time.Second || d > 10*time.Minute {
		t.Errorf("start time of this process is %v, which is %v from now", got, d)
	}
}
