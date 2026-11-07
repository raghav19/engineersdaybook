// Package testutil builds the fakes that the tests of the delegate share.
package testutil

import (
	"database/sql"
	"os/exec"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"
)

// Run is one row of the table "run" in the fake msb.db.
type Run struct {
	Sandbox string
	PID     int
	Status  string
}

// NewMsbDB writes a fake msb.db with the tables "sandbox" and "run".
// The columns are the ones of msb 0.7.13 that the delegate reads.
func NewMsbDB(t *testing.T, runs []Run) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "msb.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, q := range []string{
		`CREATE TABLE sandbox (id integer PRIMARY KEY AUTOINCREMENT, name text NOT NULL UNIQUE)`,
		`CREATE TABLE run (id integer PRIMARY KEY AUTOINCREMENT, sandbox_id integer NOT NULL, pid integer, status text NOT NULL)`,
	} {
		if _, err := db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	ids := map[string]int64{}
	for _, r := range runs {
		id, ok := ids[r.Sandbox]
		if !ok {
			res, err := db.Exec(`INSERT INTO sandbox (name) VALUES (?)`, r.Sandbox)
			if err != nil {
				t.Fatal(err)
			}
			id, _ = res.LastInsertId()
			ids[r.Sandbox] = id
		}
		if _, err := db.Exec(`INSERT INTO run (sandbox_id, pid, status) VALUES (?, ?, ?)`, id, r.PID, r.Status); err != nil {
			t.Fatal(err)
		}
	}
	return path
}

// StartProcess starts a process whose command line has "--name <name>", like a VMM.
// The test kills it at the end. The caller gets the process to kill it earlier.
func StartProcess(t *testing.T, name string) *exec.Cmd {
	t.Helper()
	cmd := exec.Command("sh", "-c", "sleep 60; true", "msb", "--name", name)
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	})
	return cmd
}
