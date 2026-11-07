// Command msbvm is a SPIRE workload attestor plugin. It maps the pid of an msb
// VMM to the selectors name:<vm> and id:<sandbox-id>.
package main

import (
	"github.com/spiffe/spire-plugin-sdk/pluginmain"
	workloadattestorv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/plugin/agent/workloadattestor/v1"
	configv1 "github.com/spiffe/spire-plugin-sdk/proto/spire/service/common/config/v1"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/plugin/internal/attestor"
)

func main() {
	p := attestor.New()
	pluginmain.Serve(
		workloadattestorv1.WorkloadAttestorPluginServer(p),
		configv1.ConfigServiceServer(p),
	)
}
