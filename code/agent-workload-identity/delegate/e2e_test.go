//go:build e2e

package main

// This file has the test that tests/e2e.sh runs against a real SPIRE agent. The
// script sets E2E_SOCKET (the admin socket) and E2E_PID (the pid to send). It
// runs this test as a binary that the delegate entry of the test server allows
// to call the Delegated Identity API. The tag e2e keeps the test out of
// "go test ./...".

import (
	"context"
	"errors"
	"os"
	"strconv"
	"testing"
	"time"
)

// TestPidIsRefused sends one pid to the agent. The agent must answer with zero
// SVIDs. Any other answer, for example PermissionDenied, is a failure: the test
// caller is allowed, so only the pid can be the reason for the refusal.
func TestPidIsRefused(t *testing.T) {
	socket := os.Getenv("E2E_SOCKET")
	pid, err := strconv.Atoi(os.Getenv("E2E_PID"))
	if socket == "" || err != nil {
		t.Fatalf("set E2E_SOCKET and E2E_PID to a number (pid parse error: %v)", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	svid, err := fetchSVID(ctx, socket, pid, "spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/sandbox-dev")
	if !errors.Is(err, errRefused) {
		t.Fatalf("pid %d: want errRefused (zero SVIDs), got svid=%v err=%v", pid, svid, err)
	}
}
