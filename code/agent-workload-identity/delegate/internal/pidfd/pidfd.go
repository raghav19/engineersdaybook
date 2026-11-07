// Package pidfd holds a pidfd, so that the delegate never uses a recycled pid.
package pidfd

import (
	"errors"
	"fmt"

	"golang.org/x/sys/unix"
)

// PIDFD is an open pidfd of one process.
type PIDFD struct {
	fd int
}

// Open opens a pidfd for the pid. It fails if the process is gone.
func Open(pid int) (*PIDFD, error) {
	fd, err := unix.PidfdOpen(pid, 0)
	if err != nil {
		return nil, fmt.Errorf("open pidfd of pid %d: %w", pid, err)
	}
	return &PIDFD{fd: fd}, nil
}

// Alive returns nil if the process has not exited. A pidfd becomes readable
// when the process exits. This is also true for a zombie that nobody reaped.
func (p *PIDFD) Alive() error {
	fds := []unix.PollFd{{Fd: int32(p.fd), Events: unix.POLLIN}}
	for {
		n, err := unix.Poll(fds, 0)
		if errors.Is(err, unix.EINTR) {
			continue
		}
		if err != nil {
			return fmt.Errorf("poll pidfd: %w", err)
		}
		if n > 0 {
			return errors.New("process exited")
		}
		return nil
	}
}

// Close closes the pidfd.
func (p *PIDFD) Close() error {
	return unix.Close(p.fd)
}
