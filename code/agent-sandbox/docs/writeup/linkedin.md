Your AI agent chooses its commands while it runs.

You cannot review them in advance. A hidden instruction in an issue or a web page can change what it does next.

Anthropic ran a red-team test. Claude sent ~/.aws/credentials to an attacker 24 times out of 25. Their conclusion: "The only defense that holds in this situation is the environment."

So I put the boundary outside the agent.

I run Claude Code in a Docker Sandboxes (sbx) microVM. One command starts it:

task sandbox:run

What you get:
→ Its own kernel. A container shares the host kernel.
→ Controlled egress. A host proxy blocks every host that no rule allows.
→ No credentials inside. The host injects a short-lived token on one domain only.
→ Your work stays yours. The agent edits a private clone. You fetch its branch and review it.

And it still feels like your machine. VS Code opens on the sandbox with your extensions, your shell, and your tools. They come from files in the repo. To change them, edit, commit, and restart. No image rebuild.

This is not complete protection. An allow-list is a capability grant. Prompt injection still works. You must review what you merge. The post lists every gap.

Blog post, kit, and demo video:
[link]

How do you sandbox your agents today?

#AIAgents #ClaudeCode #DockerSandboxes #DevEx #Security
