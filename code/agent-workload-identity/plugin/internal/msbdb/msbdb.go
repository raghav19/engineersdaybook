// Package msbdb reads the database of msb (microsandbox), msb.db. The plugin
// opens it read-only. The tables "sandbox" and "run" are internal to msb, so
// the package checks their columns before use.
package msbdb

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// TestedMsbVersion is the msb version whose tables this package was tested with.
const TestedMsbVersion = "0.7.13"

// ErrNoRun means that no row of the table "run" matches.
var ErrNoRun = errors.New("no running row")

// requiredColumns are the columns that the query needs.
var requiredColumns = []struct {
	table   string
	columns []string
}{
	{"sandbox", []string{"id", "name"}},
	{"run", []string{"sandbox_id", "pid", "status", "started_at"}},
}

// DB is a read-only handle to msb.db.
type DB struct {
	db *sql.DB
}

// Open opens the file read-only. The file is not read until the first query.
func Open(path string) (*DB, error) {
	db, err := sql.Open("sqlite", "file:"+path+"?mode=ro")
	if err != nil {
		return nil, err
	}
	return &DB{db: db}, nil
}

// Close closes the handle.
func (d *DB) Close() error { return d.db.Close() }

// CheckSchema fails if "sandbox" or "run" lack a column that RunStartedAt needs.
func (d *DB) CheckSchema(ctx context.Context) error {
	for _, t := range requiredColumns {
		have, err := d.columns(ctx, t.table)
		if err != nil {
			return fmt.Errorf("read the columns of table %s (this plugin was tested with msb %s only): %w", t.table, TestedMsbVersion, err)
		}
		var missing []string
		for _, c := range t.columns {
			if !have[c] {
				missing = append(missing, c)
			}
		}
		if len(missing) > 0 {
			return fmt.Errorf("table %s lacks the columns %s. This plugin was tested with msb %s only, and msb can change its tables",
				t.table, strings.Join(missing, ", "), TestedMsbVersion)
		}
	}
	return nil
}

func (d *DB) columns(ctx context.Context, table string) (map[string]bool, error) {
	// The table name comes from the constant above, never from input.
	rows, err := d.db.QueryContext(ctx, "SELECT name FROM pragma_table_info('"+table+"')")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	have := map[string]bool{}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		have[name] = true
	}
	return have, rows.Err()
}

// RunStartedAt returns the start time (UTC) of the run of sandbox id/name that
// has this pid and the status Running. It returns ErrNoRun if there is none.
func (d *DB) RunStartedAt(ctx context.Context, id, name string, pid int) (time.Time, error) {
	var started string
	err := d.db.QueryRowContext(ctx,
		`SELECT r.started_at FROM run r JOIN sandbox s ON s.id = r.sandbox_id
		 WHERE s.id = ? AND s.name = ? AND r.pid = ? AND r.status = 'Running'`,
		id, name, pid).Scan(&started)
	if errors.Is(err, sql.ErrNoRows) {
		return time.Time{}, fmt.Errorf("sandbox %s/%s pid %d: %w", name, id, pid, ErrNoRun)
	}
	if err != nil {
		return time.Time{}, err
	}
	t, err := time.Parse("2006-01-02 15:04:05.999999999", started)
	if err != nil {
		return time.Time{}, fmt.Errorf("started_at %q: %w", started, err)
	}
	return t, nil
}
