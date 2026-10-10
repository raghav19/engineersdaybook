# ext-mcp

ExtMCP guardrail service for the gateway (gRPC, h2c, port 4445). `rules.py` holds the decisions as pure functions
with unit tests (`python3 -m unittest discover -s tests`). `server.py` wraps them in the ExtMCP gRPC contract and is
**not written yet**: the contract is `crates/protos/proto/ext_mcp.proto` in agentgateway, to be vendored at the
pinned tag into `proto/` and checked against `AgentgatewayPolicy.spec.backend.mcp.guardrails` before coding.
