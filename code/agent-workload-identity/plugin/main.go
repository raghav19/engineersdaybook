// Command msbvm is a SPIRE workload attestor plugin for microsandbox (msb).
// It turns the pid of the VMM of a microVM into two selectors: name:<vm> and
// id:<sandbox-id>. A registration entry matches these selectors.
//
// How it works. The SPIRE agent runs this program as a child process. The agent
// calls Attest with the pid of a process. Attest does two checks:
//  1. The exe of the process is msb.                         (plugin.go)
//  2. msb.db has a "run" row with this pid and the status Running. The row
//     gives the name and the sandbox ID of the VM.           (msbdb.go)
//
// If both checks pass, Attest returns the selectors. If a check fails, it
// returns no selectors, and the agent returns zero SVIDs to the delegate.
//
// Files:
//
//	main.go    starts the plugin
//	plugin.go  the plugin: Configure and Attest
//	msbdb.go   reads msb.db
package main

import (
	"github.com/spiffe/spire-plugin-sdk/pluginmain"
	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"
)

func main() {
	p := New()
	pluginmain.Serve(
		workloadattestorv1.WorkloadAttestorPluginServer(p),
		configv1.ConfigServiceServer(p),
	)
}
