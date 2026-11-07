// File msbdb.go reads msb.db, the database of msb.
//
// msb writes a row in the table "run" each time it starts a VM. The row has the
// pid of the VMM and the status (for example Running). Nobody but msb writes
// it, so it is the record that tells which pid runs which VM. The plugin opens
// the file read-only.
//
// The tables "sandbox" and "run" are internal to msb. msb can change them in a
// new version. The plugin was tested with the version below.
package main

import (
	"context"
	"database/sql"
	"errors"
	"strconv"

	_ "modernc.org/sqlite" // the driver of database/sql, no cgo
)

// testedMsbVersion is the msb version whose tables the tests assume.
const testedMsbVersion = "0.7.13"

// The query of the plugin. It gives the name and the ID of the VM that runs as
// one pid. If there are several rows for a pid, for example one old and one
// new, the newest row wins.
const runningVM = `SELECT s.name, s.id FROM run r JOIN sandbox s ON s.id = r.sandbox_id
	WHERE r.pid = ? AND r.status = 'Running' ORDER BY r.id DESC LIMIT 1`

// open opens msb.db read-only. It does not read the file yet.
func open(path string) (*sql.DB, error) {
	return sql.Open("sqlite", "file:"+path+"?mode=ro")
}

// checkTables runs the query of the plugin once. It fails if the file cannot be
// read, or if a table or a column is missing.
func checkTables(ctx context.Context, path string) error {
	db, err := open(path)
	if err != nil {
		return err
	}
	defer db.Close()
	if err := db.QueryRowContext(ctx, runningVM, 0).Scan(new(string), new(int)); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	return nil
}

// lookup returns the name and the sandbox ID of the VM that runs as this pid.
// It returns found=false if msb.db has no running row for the pid.
func lookup(ctx context.Context, path string, pid int) (name, id string, found bool, err error) {
	db, err := open(path)
	if err != nil {
		return "", "", false, err
	}
	defer db.Close()
	var sandboxID int
	err = db.QueryRowContext(ctx, runningVM, pid).Scan(&name, &sandboxID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", false, nil
	}
	if err != nil {
		return "", "", false, err
	}
	return name, strconv.Itoa(sandboxID), true, nil
}
