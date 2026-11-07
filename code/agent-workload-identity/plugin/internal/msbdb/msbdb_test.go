package msbdb

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/plugin/internal/msbtest"
)

func TestCheckSchema(t *testing.T) {
	tests := []struct {
		name       string
		statements []string
		wantErr    []string // text that the error must have
	}{
		{name: "full schema", statements: []string{msbtest.Schema}},
		{
			name: "extra columns are fine",
			statements: []string{
				`CREATE TABLE sandbox (id INTEGER, name TEXT, status TEXT, config TEXT)`,
				`CREATE TABLE run (id INTEGER, sandbox_id INTEGER, pid INTEGER, status TEXT, started_at TEXT, exit_code INTEGER)`,
			},
		},
		{
			name: "run lacks started_at",
			statements: []string{
				`CREATE TABLE sandbox (id INTEGER, name TEXT)`,
				`CREATE TABLE run (id INTEGER, sandbox_id INTEGER, pid INTEGER, status TEXT)`,
			},
			wantErr: []string{"table run", "started_at", "0.7.13"},
		},
		{
			name: "sandbox lacks name",
			statements: []string{
				`CREATE TABLE sandbox (id INTEGER)`,
				`CREATE TABLE run (id INTEGER, sandbox_id INTEGER, pid INTEGER, status TEXT, started_at TEXT)`,
			},
			wantErr: []string{"table sandbox", "name", "0.7.13"},
		},
		{
			name:       "no run table",
			statements: []string{`CREATE TABLE sandbox (id INTEGER, name TEXT)`},
			wantErr:    []string{"table run", "sandbox_id", "pid", "status", "started_at", "0.7.13"},
		},
		{name: "empty database", statements: []string{`CREATE TABLE other (x INTEGER)`}, wantErr: []string{"table sandbox", "0.7.13"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			d := open(t, msbtest.Create(t, tc.statements...))
			err := d.CheckSchema(context.Background())
			if len(tc.wantErr) == 0 {
				if err != nil {
					t.Fatalf("CheckSchema() = %v, want nil", err)
				}
				return
			}
			if err == nil {
				t.Fatal("CheckSchema() = nil, want an error")
			}
			for _, s := range tc.wantErr {
				if !strings.Contains(err.Error(), s) {
					t.Errorf("error %q does not contain %q", err, s)
				}
			}
		})
	}
}

func TestOpenMissingFile(t *testing.T) {
	d, err := Open("/nonexistent/msb.db")
	if err == nil {
		defer d.Close()
		err = d.CheckSchema(context.Background())
	}
	if err == nil {
		t.Fatal("want an error for a file that does not exist")
	}
}

func TestOpenIsReadOnly(t *testing.T) {
	path := msbtest.Create(t, msbtest.Schema)
	d := open(t, path)
	if _, err := d.db.Exec(`INSERT INTO sandbox (name, status) VALUES ('x', 'Running')`); err == nil {
		t.Fatal("write succeeded on a read-only handle")
	}
}

func TestRunStartedAt(t *testing.T) {
	path := msbtest.Create(t, msbtest.Schema,
		`INSERT INTO sandbox (id, name, status) VALUES (184, 'sandbox-dev', 'Running'), (185, 'other', 'Running')`,
		// An old run, then the current run of sandbox-dev, then a run of another sandbox.
		`INSERT INTO run (sandbox_id, pid, status, started_at) VALUES
		   (184, 1000, 'Terminated', '2026-11-05 08:00:00.000000000'),
		   (184, 2631586, 'Running', '2026-11-06 10:24:31.959941430'),
		   (185, 4000, 'Running', '2026-11-06 11:00:00'),
		   (185, 5000, 'Crashed', '2026-11-06 12:00:00.5')`,
	)
	d := open(t, path)
	tests := []struct {
		name      string
		id, vm    string
		pid       int
		want      time.Time
		wantNoRun bool
	}{
		{name: "the running row", id: "184", vm: "sandbox-dev", pid: 2631586, want: time.Date(2026, 11, 6, 10, 24, 31, 959941430, time.UTC)},
		{name: "start time without a fraction", id: "185", vm: "other", pid: 4000, want: time.Date(2026, 11, 6, 11, 0, 0, 0, time.UTC)},
		{name: "wrong pid", id: "184", vm: "sandbox-dev", pid: 999, wantNoRun: true},
		{name: "pid of an old run", id: "184", vm: "sandbox-dev", pid: 1000, wantNoRun: true},
		{name: "run is not Running", id: "185", vm: "other", pid: 5000, wantNoRun: true},
		{name: "wrong name", id: "184", vm: "other", pid: 2631586, wantNoRun: true},
		{name: "wrong ID", id: "185", vm: "sandbox-dev", pid: 2631586, wantNoRun: true},
		{name: "pid of another sandbox", id: "184", vm: "sandbox-dev", pid: 4000, wantNoRun: true},
		{name: "ID is not a number", id: "184 OR 1=1", vm: "sandbox-dev", pid: 2631586, wantNoRun: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := d.RunStartedAt(context.Background(), tc.id, tc.vm, tc.pid)
			if tc.wantNoRun {
				if !errors.Is(err, ErrNoRun) {
					t.Fatalf("RunStartedAt() error = %v, want ErrNoRun", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if !got.Equal(tc.want) {
				t.Errorf("RunStartedAt() = %v, want %v", got, tc.want)
			}
		})
	}
}

func open(t *testing.T, path string) *DB {
	t.Helper()
	d, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { d.Close() })
	return d
}
