// Package vmm finds the pid of the VMM that runs one microVM.
package vmm

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"

	_ "modernc.org/sqlite"
)

// FindPID returns the pid of the VMM of the VM. It reads the newest run row
// with status Running from msb.db, which it opens read-only. It then checks
// that the command line of the pid has "--name <vm>". This check is only a
// sanity check. The plugin msbvm does the full check.
func FindPID(ctx context.Context, dbPath, vm string) (int, error) {
	pid, err := runningPID(ctx, dbPath, vm)
	if err != nil {
		return 0, err
	}
	if err := checkCmdline(pid, vm); err != nil {
		return 0, err
	}
	return pid, nil
}

func runningPID(ctx context.Context, dbPath, vm string) (int, error) {
	db, err := sql.Open("sqlite", "file:"+dbPath+"?mode=ro")
	if err != nil {
		return 0, fmt.Errorf("open msb.db: %w", err)
	}
	defer db.Close()
	var pid int
	err = db.QueryRowContext(ctx,
		`SELECT r.pid FROM run r JOIN sandbox s ON s.id = r.sandbox_id
		 WHERE s.name = ? AND r.status = 'Running' AND r.pid > 0
		 ORDER BY r.id DESC LIMIT 1`, vm).Scan(&pid)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, fmt.Errorf("no running row for VM %q in msb.db", vm)
	}
	if err != nil {
		return 0, fmt.Errorf("read msb.db: %w", err)
	}
	return pid, nil
}

func checkCmdline(pid int, vm string) error {
	raw, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/cmdline")
	if err != nil {
		return fmt.Errorf("read command line of pid %d: %w", pid, err)
	}
	args := strings.Split(strings.TrimRight(string(raw), "\x00"), "\x00")
	for i := 0; i+1 < len(args); i++ {
		if args[i] == "--name" && args[i+1] == vm {
			return nil
		}
	}
	return fmt.Errorf("command line of pid %d has no --name %s", pid, vm)
}
