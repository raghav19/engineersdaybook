// Package delegate gets the SVID of one microVM from the host SPIRE agent.
package delegate

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/agent"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/pidfd"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/vmm"
)

// ErrIDMismatch means that no SVID in the answer of the agent has the expected ID.
var ErrIDMismatch = errors.New("no SVID has the expected ID")

// Config tells the delegate which VM to ask for.
type Config struct {
	VM     string // name of the microVM
	ID     string // the SPIFFE ID that the SVID of this VM must have
	Socket string // admin socket of the host SPIRE agent
	DBPath string // msb.db
}

// hooks let the tests change the world at two points.
type hooks struct {
	afterOpen func() // after the pidfd is open
	afterCall func() // after the agent has answered
}

// Fetch finds the VMM of the VM, holds a pidfd of it and asks the agent for
// the SVID with the expected ID. The SPIRE docs say that the pid must not be
// recycled between the request and the answer. So Fetch checks the pidfd after
// the answer, and it returns no SVID if the process has exited.
func Fetch(ctx context.Context, cfg Config) (*agent.SVID, error) {
	return fetch(ctx, cfg, hooks{})
}

func fetch(ctx context.Context, cfg Config, h hooks) (*agent.SVID, error) {
	pid, err := vmm.RunningPID(ctx, cfg.DBPath, cfg.VM)
	if err != nil {
		return nil, err
	}
	fd, err := pidfd.Open(pid)
	if err != nil {
		return nil, err
	}
	defer fd.Close()
	if h.afterOpen != nil {
		h.afterOpen()
	}
	if err := checkVMM(fd, pid, cfg.VM); err != nil {
		return nil, err
	}
	svids, err := agent.FetchX509SVIDs(ctx, cfg.Socket, pid)
	if err != nil {
		return nil, err
	}
	if h.afterCall != nil {
		h.afterCall()
	}
	if err := fd.Alive(); err != nil {
		return nil, fmt.Errorf("VMM pid %d exited during the call: %w", pid, err)
	}
	return pick(svids, cfg.ID)
}

// checkVMM reads the command line first and checks the pidfd after that. The
// pid can be reused between the read of msb.db and the open of the pidfd. If
// the process has not exited after the read, the command line belongs to the
// process of the pidfd.
func checkVMM(fd *pidfd.PIDFD, pid int, vm string) error {
	cmdErr := vmm.CheckCmdline(pid, vm)
	if err := fd.Alive(); err != nil {
		return fmt.Errorf("VMM pid %d: %w", pid, err)
	}
	return cmdErr
}

// pick returns the SVID with the expected ID. It does not take the first one,
// because the agent returns the SVIDs of all entries that match the process.
func pick(svids []*agent.SVID, id string) (*agent.SVID, error) {
	got := make([]string, len(svids))
	for i, s := range svids {
		if s.ID == id {
			return s, nil
		}
		got[i] = s.ID
	}
	return nil, fmt.Errorf("%w %s, the agent returned: %s", ErrIDMismatch, id, strings.Join(got, ", "))
}
