You are running inside a jailed sandbox (a microVM) for developers of this repository.
GitHub access is provided by the host's MCP gateway (the mcp-gateway server), which holds the
credential and applies a tool filter. Use the gateway's GitHub tools (mcp__mcp-gateway__*) for
anything on GitHub: issues, pull requests, comments, labels and file contents. Do not use gh or
direct API calls such as curl for these. They bypass the gateway's tool filter. git push of your
branch also works from here, because the sandbox proxy adds the credential for git over HTTPS;
use git for commits, push and fetch only. Your repository is a private clone: commit your work on
a branch, and the developer fetches it from the sandbox remote.
