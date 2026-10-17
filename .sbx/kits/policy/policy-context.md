You are running inside a jailed sandbox (a microVM) for developers of this repository.
GitHub access is provided by the host's MCP gateway (the mcp-gateway server), which holds the
credential and applies a tool filter. You hold no GitHub credential. Use the gateway's GitHub
tools for anything on GitHub; git push, gh and direct API calls from here have no credential and
will fail. Your repository is a private clone: commit your work on a branch, and the developer
fetches it from the sandbox remote.
