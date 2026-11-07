// Package delegate gets the SVID of one microVM from the host SPIRE agent.
package delegate

import (
	"context"
	"fmt"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/agent"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/pidfd"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/vmm"
)

// Config tells the delegate which VM to ask for.
type Config struct {
	VM     string // name of the microVM
	Socket string // admin socket of the host SPIRE agent
	DBPath string // msb.db
}

// Fetch finds the VMM of the VM, holds a pidfd of it and asks the agent for
// its SVID. It does not call the agent if the process has exited. It holds
// the pidfd until it returns.
func Fetch(ctx context.Context, cfg Config) (*agent.SVID, error) {
	return fetch(ctx, cfg, nil)
}

// fetch is Fetch with a hook that tests use. The hook runs after the pidfd is open.
func fetch(ctx context.Context, cfg Config, afterOpen func()) (*agent.SVID, error) {
	pid, err := vmm.FindPID(ctx, cfg.DBPath, cfg.VM)
	if err != nil {
		return nil, err
	}
	fd, err := pidfd.Open(pid)
	if err != nil {
		return nil, err
	}
	defer fd.Close()
	if afterOpen != nil {
		afterOpen()
	}
	if err := fd.Alive(); err != nil {
		return nil, fmt.Errorf("VMM pid %d: %w", pid, err)
	}
	return agent.FetchX509SVID(ctx, cfg.Socket, pid)
}
