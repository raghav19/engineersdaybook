// Package proc reads facts about a process from /proc.
package proc

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// clockTicksPerSecond is the unit of the start time in /proc/<pid>/stat.
// TODO: read AT_CLKTCK from /proc/self/auxv instead of this constant. Check:
// the value must equal the output of `getconf CLK_TCK`. The kernel reports
// /proc times in USER_HZ, which is 100 on x86_64 and arm64.
const clockTicksPerSecond = 100

// startTimeField is the position of "starttime" in /proc/<pid>/stat. Counting
// starts at 1, as in proc(5).
const startTimeField = 22

// StartTime returns the start time of a process in UTC. It adds the boot time
// from <procRoot>/stat to the start ticks from <procRoot>/<pid>/stat.
// The resolution of the boot time is one second.
func StartTime(procRoot string, pid int) (time.Time, error) {
	raw, err := os.ReadFile(filepath.Join(procRoot, strconv.Itoa(pid), "stat"))
	if err != nil {
		return time.Time{}, err
	}
	ticks, err := startTicks(string(raw))
	if err != nil {
		return time.Time{}, err
	}
	btime, err := bootTime(filepath.Join(procRoot, "stat"))
	if err != nil {
		return time.Time{}, err
	}
	return time.Unix(btime, 0).Add(time.Duration(ticks) * time.Second / clockTicksPerSecond).UTC(), nil
}

// startTicks reads field 22 of a stat line. The comm field (field 2) can hold
// spaces and parentheses, so the parse starts after the last ")".
func startTicks(stat string) (int64, error) {
	end := strings.LastIndexByte(stat, ')')
	if end < 0 {
		return 0, fmt.Errorf("stat has no closing parenthesis")
	}
	fields := strings.Fields(stat[end+1:]) // the first field here is field 3
	idx := startTimeField - 3
	if len(fields) <= idx {
		return 0, fmt.Errorf("stat has %d fields after comm, need %d", len(fields), idx+1)
	}
	ticks, err := strconv.ParseInt(fields[idx], 10, 64)
	if err != nil {
		return 0, fmt.Errorf("start time: %w", err)
	}
	return ticks, nil
}

func bootTime(statPath string) (int64, error) {
	raw, err := os.ReadFile(statPath)
	if err != nil {
		return 0, err
	}
	sc := bufio.NewScanner(bytes.NewReader(raw))
	for sc.Scan() {
		if v, ok := strings.CutPrefix(sc.Text(), "btime "); ok {
			btime, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
			if err != nil {
				return 0, fmt.Errorf("btime: %w", err)
			}
			return btime, nil
		}
	}
	return 0, fmt.Errorf("no btime line in %s", statPath)
}

// Exe returns the target of the link <procRoot>/<pid>/exe.
func Exe(procRoot string, pid int) (string, error) {
	return os.Readlink(filepath.Join(procRoot, strconv.Itoa(pid), "exe"))
}

// Cmdline returns the raw content of <procRoot>/<pid>/cmdline.
func Cmdline(procRoot string, pid int) ([]byte, error) {
	return os.ReadFile(filepath.Join(procRoot, strconv.Itoa(pid), "cmdline"))
}
