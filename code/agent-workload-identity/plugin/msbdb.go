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

	_ "modernc.org/sqlite" // the driver of database/sql, no cgo
)

// testedMsbVersion is the msb version whose tables the tests assume.
const testedMsbVersion = "0.7.13"

// open opens msb.db read-only. It does not read the file yet.
func open(path string) (*sql.DB, error) {
	return sql.Open("sqlite", "file:"+path+"?mode=ro")
}

// checkTables runs the real query of the plugin and asks for no rows. It
// fails if the file cannot be read, or if a table or a column is missing.
func checkTables(ctx context.Context, path string) error {
	db, err := open(path)
	if err != nil {
		return err
	}
	defer db.Close()
	rows, err := db.QueryContext(ctx, `SELECT s.id, s.name, r.pid, r.status
		FROM run r JOIN sandbox s ON s.id = r.sandbox_id LIMIT 0`)
	if err != nil {
		return err
	}
	return rows.Close()
}

// isRunning reports whether msb.db has a "run" row of the VM with this ID and
// name, with this pid and the status Running.
func isRunning(ctx context.Context, path, id, name string, pid int) (bool, error) {
	db, err := open(path)
	if err != nil {
		return false, err
	}
	defer db.Close()
	var one int
	err = db.QueryRowContext(ctx,
		`SELECT 1 FROM run r JOIN sandbox s ON s.id = r.sandbox_id
		 WHERE s.id = ? AND s.name = ? AND r.pid = ? AND r.status = 'Running'`,
		id, name, pid).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}
