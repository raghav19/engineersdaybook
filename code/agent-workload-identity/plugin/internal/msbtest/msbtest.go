// Package msbtest builds fake msb.db files for tests. It has only the columns
// that the plugin reads.
package msbtest

import (
	"database/sql"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"
)

// Schema has the two tables and the columns that the plugin needs.
const Schema = `
CREATE TABLE sandbox (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, status TEXT NOT NULL);
CREATE TABLE run (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, sandbox_id INTEGER NOT NULL, pid INTEGER, status TEXT NOT NULL, started_at TEXT);
`

// Create makes a database file in a temporary folder. It runs each statement
// in order and returns the path of the file.
func Create(t *testing.T, statements ...string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "msb.db")
	db, err := sql.Open("sqlite", "file:"+path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, s := range statements {
		if _, err := db.Exec(s); err != nil {
			t.Fatalf("%s: %v", s, err)
		}
	}
	return path
}
