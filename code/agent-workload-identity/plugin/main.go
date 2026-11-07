// Command msbvm is a SPIRE workload attestor plugin for microsandbox (msb).
// It turns the pid of the VMM of a microVM into two selectors: name:<vm> and
// id:<sandbox-id>. A registration entry matches these selectors.
//
// How it works. The SPIRE agent runs this program as a child process. The agent
// calls Attest with the pid of a process. Attest does three checks:
//  1. The exe of the process is msb.                        (vmm.go)
//  2. The command line is "msb machine --name <vm> --sandbox-id <id>".  (vmm.go)
//  3. msb.db has a "run" row with the same VM, the same pid and the status
//     Running.                                              (msbdb.go)
//
// If all three checks pass, Attest returns the selectors. If the process is not
// a VMM, it returns no selectors. If the process looks like a VMM but msb.db
// does not know it, it returns an error. In both cases the agent returns zero
// SVIDs.
//
// Files:
//
//	main.go    starts the plugin
//	plugin.go  the plugin: Configure and Attest
//	vmm.go     reads the exe and the command line of a process
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
