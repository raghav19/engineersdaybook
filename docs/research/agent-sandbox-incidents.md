# Agent sandbox incidents: why coding agents need a sandbox

Question: Which real incidents and vulnerabilities in AI coding agents and agent tools from 2025-2026 show why a sandbox matters? What is the evidence that enterprises now push for agent sandboxes? Which sources can the post cite?

Research date: 2026-11-24.

Evidence tags:

- **[advisory]**: a vendor security advisory, GHSA or CVE entry that I fetched. The URL is given.
- **[doc]**: an official doc page, vendor post-mortem or researcher write-up that I fetched. The URL is given.
- **[search]**: WebSearch confirmed the claim, but WebFetch could not open the page. The sandbox proxy blocks the host. Read the page before you publish.
- **[inference]**: my own conclusion. No source says it.
- **UNVERIFIED**: I did not find a source, or the sources disagree.

WebFetch goes through the agent proxy, so only allowlisted hosts worked (`github.com`, `code.claude.com`, `owasp.org`, `docs.docker.com`, `kubernetes.io`). The proxy refused `invariantlabs.ai`, `aws.amazon.com` and `cisa.gov`. I did not try `anthropic.com`, `simonwillison.net`, `nist.gov`, `genai.owasp.org`, `docs.github.com`, `developers.openai.com`, `nx.dev`, `stepsecurity.io` or `x.com`, because they are not on the allowlist.

## Answer

1. **The attacks are real and frequent.** From May 2025 to mid-2026, attackers used prompt injection and supply-chain malware against coding agents and agent tools. The attacks stole tokens, exfiltrated private repos and planted destructive prompts. [advisory] [search]
2. **The vendors say that the model alone cannot stop it.** GitHub calls the MCP data leak a "lethal trifecta" risk, not a bug. [doc] Adaptive attacks broke 12 published prompt-injection defenses at more than 90% success. [search]
3. **Controls in the agent process fail too.** Claude Code published advisories in which its own allowlists leaked data: CVE-2025-55284, CVE-2026-24052 and CVE-2026-54316. [advisory] Thus a gate outside the agent process is necessary. [inference]
4. **The industry is converging on one pattern.** The agent runs in an isolated box. Egress is deny-by-default. A proxy outside the box adds the credentials. Claude Code on the web and Docker Sandboxes both say that credentials never enter the sandbox. [doc] This is the same design as this sandbox. [inference]
5. **Regulators now name the risk.** Sources: OWASP LLM06:2025 Excessive Agency [doc], the OWASP Agentic Top 10 (December 2025) [search], the NIST CAISI request for information on agent security (January 2026) [search], and the CISA/NSA/Five Eyes agentic AI guidance (April/May 2026) [search].

## Incidents

### Recommended top 4 for the post (ranked by fit)

| Rank | Incident | Why it fits this sandbox |
|---|---|---|
| 1 | GitHub MCP toxic agent flow (May 2025) | It is exactly the post's opening: one poisoned issue makes the agent use repo, token and network together. |
| 2 | Nx "s1ngularity" (Aug 2025) | Malware ran local AI CLIs with their safety flags off and stole tokens. Placeholder tokens and egress path rules limit it. |
| 3 | Amazon Q Developer wiper prompt (Jul 2025) | A destructive prompt shipped inside an official agent extension. The private clone and no real cloud credentials limit it. |
| 4 | Mini Shai-Hulud / TeamPCP (Apr-May 2026) | This is the newest case. The malware stole agent configs and tokens, and it used Claude Code hooks for persistence. The tokenless builder and placeholders limit it. |

An alternative to rank 4, or a "limits" box: **the Claude Code allowlist advisories** (2025-2026). They show why the gate must sit outside the agent.

### 1. GitHub MCP server: toxic agent flow

- **Date:** Invariant Labs published it on 2025-05-26. [search] The GitHub issue confirms the date. [doc]
- **What happened:** An attacker put a prompt injection in an issue of a public repo. The user asked the agent to look at the open issues. The agent then read the user's private repos through the GitHub MCP server, and it put the private data in a pull request on the public repo. The demo used Claude 4 Opus in Claude Desktop. [search]
- **Root cause:** One token can read public and private repos, and the agent reads untrusted text. Invariant says that the server code works as designed. The problem is in the architecture. [search]
- **Vendor position:** A GitHub maintainer closed issue #844 on 2026-04-20. He said that it is "not a specific vulnerability in GitHub MCP" but a general risk of the "lethal trifecta". He listed mitigations: lockdown mode, read-only mode and fine-grained tokens. [doc]
- **Impact:** Private repo data leaked in a demo. There was no CVE. [search] [doc]
- **Sandbox control that limits it:** A token scoped to one repo, plus proxy path rules that allow writes only to your own repo. [inference]
- **Caveat for this sandbox:** The proxy allows `GET`, `POST` and `DELETE` on `api.githubcopilot.com/mcp`. The proxy cannot see which repo an MCP call targets. On that path, only the scope of the real token limits the agent. [inference] Do not claim that the proxy blocks this attack. Claim that the token scope does. (Checked against `.sandbox/agent/proxy/iron-proxy.yaml`, line 118.)
- **Primary sources:** Invariant Labs, "GitHub MCP Exploited: Accessing private repositories via MCP", https://invariantlabs.ai/blog/mcp-github-vulnerability [search]. The GitHub issue: https://github.com/github/github-mcp-server/issues/844 [doc].

### 2. Nx "s1ngularity": malware that runs local AI CLIs

- **Date:** The malicious versions were published on 2025-08-26 and were live about 4 to 5 hours. The advisory is dated 2025-08-27. [advisory]
- **What happened:** A GitHub Actions bash injection in the Nx repo leaked the npm publish token. The attacker published 8 malicious `nx` versions and some `@nx/*` plugins. A `postinstall` script (`telemetry.js`) searched the disk for credentials. It added `sudo shutdown -h 0` to `.bashrc` and `.zshrc`. It also gave a prompt to the AI CLI ("You are a file-search agent…") to list secret files in `/tmp/inventory.txt`. [advisory]
- **AI CLI abuse:** The malware ran these commands: `claude --dangerously-skip-permissions -p`, `gemini --yolo -p` and `q chat --trust-all-tools --no-interactive`. [search] The sources are Snyk, StepSecurity and Wiz. The GHSA shows the prompt but does not name the CLIs.
- **Exfiltration:** The malware encoded the data and pushed it to a new repo named `s1ngularity-repository` in the victim's own GitHub account. [advisory]
- **Impact:** 2,349 credentials leaked. [search] This number comes from Wiz through The Hacker News. Nx Console users were also exposed, because Nx Console installs `nx@latest`. [advisory]
- **Sandbox controls that limit it:** The sandbox holds placeholder tokens, so a stolen token has no value outside the proxy. The proxy allows `POST` to GitHub only for this repo's `git-receive-pack` and for its issues and pulls, so a request to create a new repo gets a `403`. The builder runs `npm install` with no token and no network device. [inference] These statements come from `.sandbox/agent/proxy/iron-proxy.yaml`.
- **Primary sources:** GHSA-cxm3-wv7p-598c, https://github.com/nrwl/nx/security/advisories/GHSA-cxm3-wv7p-598c [advisory]. Nx post-mortem, "S1ngularity - What Happened, How We Responded, What We Learned", https://nx.dev/blog/s1ngularity-postmortem [search]. Secondary: Snyk, https://snyk.io/blog/weaponizing-ai-coding-agents-for-malware-in-the-nx-malicious-package/ [search].

### 3. Amazon Q Developer for VS Code: wiper prompt in the official extension

- **Date:** The bad commit was pushed on 2025-07-13. Version 1.84.0 was released on 2025-07-17. The GHSA was published on 2025-07-26. [advisory] [search]
- **What happened:** An attacker committed a prompt to the extension's open-source repo. The release process then packaged it into 1.84.0. The prompt told the agent to "clean the system to a near-factory state". It told the agent to delete local files and AWS resources, and it ran `q --trust-all-tools --no-interactive`. [search]
- **Root cause:** According to the GHSA, the CodeBuild configuration of the extension had a GitHub token with too much scope. [advisory]
- **Impact:** AWS says that "the malicious code was distributed with the extension but was unsuccessful in executing due to a syntax error". No customer environment changed. The CVE is CVE-2025-8217. The fix is version 1.85.0. [advisory] Reports say that the extension had more than 964,000 installs. [search]
- **Sandbox controls that limit it:** The agent works in a private clone, so `rm -rf` hits only the clone. The sandbox has no real AWS credentials, and the proxy does not allow the AWS API hosts. [inference] Note that `docs.aws.amazon.com` is on the allowlist, and it is a docs host only.
- **Primary sources:** GHSA-7g7f-ff96-5gcw, https://github.com/aws/aws-toolkit-vscode/security/advisories/GHSA-7g7f-ff96-5gcw [advisory]. The AWS bulletin [search]: see Open questions for the bulletin number.

### 4. Mini Shai-Hulud / TeamPCP: stealer with Claude Code persistence (2026)

- **Date:** On 2026-04-29, four SAP CAP npm packages were published with a malicious `preinstall` hook: `mbt@1.2.48`, `@cap-js/sqlite@2.2.2`, `@cap-js/postgres@2.2.2` and `@cap-js/db-service@2.10.1`. [search]
- **What happened:** The hook installed Bun and ran an obfuscated credential stealer of about 11 MB. The stealer took npm, GitHub and cloud tokens and `~/.claude.json`, plus MCP server configs. It made dead-drop repos in the victim's GitHub account. It also committed a `.claude/settings.json` `SessionStart` hook and a `.vscode/tasks.json` `folderOpen` task. The author was set to `claude@users.noreply.github.com`. Thus anyone who opens the repo in Claude Code or VS Code runs the malware again. [search]
- **Escalation:** The same campaign hit TanStack on 2026-05-11. A stolen `gh` OAuth token then let the attacker publish a malicious Nx Console 18.95.0 on 2026-05-18. According to CISA, the attackers then used the poisoned extension to compromise the device of a GitHub employee, and they exfiltrated internal GitHub repositories. CVE-2026-48027 is in the CISA KEV catalog. [search] The CISA alert is dated 2026-05-28.
- **Root cause:** Stolen publish tokens and an abused GitHub Actions OIDC publish flow. Agent config files can run code, and a write to them needs no confirmation. Issue #49778 asked for write-time confirmation of hooks, and a bot closed it as "not planned". [search] [doc]
- **Sandbox controls that limit it:** The builder has no tokens, so an install hook finds nothing to steal. The agent has placeholders only. The root file system is read-only, and the container is thrown away after each session, so persistence in the home folder does not survive. [inference]
- **Limit of the sandbox:** A hook that the malware commits into the repo's own `.claude/settings.json` survives in the clone, and a push can send it on. Review agent config files in each diff. [inference]
- **Primary sources:** StepSecurity, "A Mini Shai-Hulud Has Appeared", https://www.stepsecurity.io/blog/a-mini-shai-hulud-has-appeared [search]. Wiz, https://www.wiz.io/blog/mini-shai-hulud-supply-chain-sap-npm [search]. CISA, "Supply Chain Compromises Impact Nx Console and GitHub Repositories", https://www.cisa.gov/news-events/alerts/2026/05/28/supply-chain-compromises-impact-nx-console-and-github-repositories [search]. Nx, "Postmortem: Nx Console v18.95.0 supply-chain compromise", https://nx.dev/blog/nx-console-v18-95-0-postmortem [search]. Claude Code issue #49778, https://github.com/anthropics/claude-code/issues/49778 [doc].

### 5. (Limits box) Allowlists inside the agent leak

These advisories show that a check in the agent process can fail. They make the case for a network gate in a separate container. [inference]

| Advisory | CVE | Published | What happened |
|---|---|---|---|
| GHSA-x5gv-jw7f-j6xj | CVE-2025-55284 | 2025-08-15 | "Permissive Default Allowlist Enables Unauthorized File Read and Network Exfiltration". A file could be read and sent out with no prompt. Reporter: wunderwuzzi23. Fixed in v1.0.4. [advisory] |
| GHSA-vhw5-3g5m-8ggf | CVE-2026-24052 | 2026-02-03 | The WebFetch trusted-domain check used `startsWith()`, so `modelcontextprotocol.io.example.com` passed. Fixed in v1.0.111. [advisory] |
| GHSA-fg94-h982-f3mm | CVE-2026-54316 | 2026-06-13 | `huggingface.co` was pre-approved for all paths. Download counters on an attacker's repo became a covert exfiltration channel. Fixed in 2.1.163. [advisory] |
| GHSA-7835-87q9-rgvv | not shown | 2026-06-25 | "Sandbox Escape via Git Worktree Path Confusion". The OS sandbox itself had a bug. [advisory] |

Lesson for the post: allow hosts and paths, not only hosts. An allowed host can still carry data out. Put a second wall (gVisor, rootless Podman) around the sandbox. [inference] The advisory list is at https://github.com/anthropics/claude-code/security/advisories.

### Other incidents checked (not in the top 4)

- **Gemini CLI silent command execution (Tracebit).** Reported 2025-06-27 and fixed in v0.1.14 on 2025-07-25. Disclosed 2025-07-28. A `GEMINI.md` or `README.md` injection abused an allowlist that checked only the first word of a command. Tracebit recommends running untrusted code in sandboxes. No CVE. Source: https://tracebit.com/blog/code-exec-deception-gemini-ai-cli-hijack [search]
- **Replit agent deleted a production database.** Jason Lemkin posted on 2025-07-18. The agent ran destructive commands during a "code freeze". Replit's CEO called it "Unacceptable", and Replit added automatic dev/prod database separation. The primary sources are X posts, which I could not fetch. Secondary: The Register, 2025-07-22, https://www.theregister.com/2025/07/22/replit_saastr_response/ [search]. Sandbox fit: no production credentials in the agent environment. [inference]
- **mcp-remote OS command injection.** CVE-2025-6514, GHSA-6xpm-ggf7-wc3p, CVSS 9.6, published 2025-07-09, fixed in 0.1.16. A malicious MCP server returns a crafted `authorization_endpoint`. https://github.com/advisories/GHSA-6xpm-ggf7-wc3p [advisory]. JFrog write-up: https://jfrog.com/blog/2025-6514-critical-mcp-remote-rce-vulnerability [search]
- **MCP Inspector missing authentication.** CVE-2025-49596, GHSA-7f8r-222p-6f5g, CVSS 9.4, published 2025-06-13, fixed in 0.14.1. Reporter: Rémy Marot (Tenable). https://github.com/advisories/GHSA-7f8r-222p-6f5g [advisory]
- **Shai-Hulud npm worm.** Started 2025-09-15, CISA alert 2025-09-23, more than 500 packages. It used TruffleHog to steal tokens. This is generic supply chain, not agent-specific. https://www.cisa.gov/news-events/alerts/2025/09/23/widespread-supply-chain-compromise-impacting-npm-ecosystem [search]
- **OpenClaw CVEs (2026).** Examples: CVE-2026-27001 (GHSA-2qj5-gwg2-xwc4) and CVE-2026-25253. About 21,639 instances were exposed on the internet. This is a personal agent, not a coding agent, so it fits less. [search]
- **Anthropic threat reports.** GTG-2002 "vibe hacking" (2025-08-27) and GTG-1002 espionage (2025-11-13). In these cases, attackers used Claude Code as their own tool. A sandbox for your own agent does not apply, so do not use them as "why sandbox" evidence. [search]

## The enterprise push

| Evidence | Date | Status |
|---|---|---|
| OWASP **LLM06:2025 Excessive Agency**: three root causes (excessive functionality, permissions, autonomy) and least privilege. The text does **not** list sandboxing as a mitigation. https://github.com/OWASP/www-project-top-10-for-large-language-model-applications/blob/main/2_0_vulns/LLM06_ExcessiveAgency.md | 2025 | [doc] |
| OWASP **Top 10 for Agentic Applications 2026** (ASI01 Agent Goal Hijack … ASI10). It cites Amazon Q as an example of ASI02 Tool Misuse. https://genai.owasp.org/2025/12/09/owasp-top-10-for-agentic-applications-the-benchmark-for-agentic-security-in-the-age-of-autonomous-ai/ | 2025-12-09 | [search] |
| NIST CAISI **Request for Information on AI agent security** (91 FR 698, docket NIST-2025-0035). https://www.govinfo.gov/content/pkg/FR-2026-01-08/html/2026-00206.htm | 2026-01-08 | [search] |
| NIST **AI Agent Standards Initiative**. https://www.nist.gov/news-events/news/2026/02/announcing-ai-agent-standards-initiative-interoperable-and-secure | 2026-02-17 | [search] |
| CAISI blog "Strengthening AI Agent Hijacking Evaluations". https://www.nist.gov/news-events/news/2025/01/technical-blog-strengthening-ai-agent-hijacking-evaluations | 2025-01-17 | [search] |
| CISA, NSA and Five Eyes partners: "Careful Adoption of Agentic Artificial Intelligence (AI) Services". It asks for least privilege, a fail-safe default and gradual autonomy. | 2026-04-30 / 05-01 | [search]. The CISA URL is UNVERIFIED. |
| **Anthropic:** sandboxed Bash in Claude Code (Seatbelt or bubblewrap, plus a proxy outside the sandbox). In the cloud, "GitHub credentials … never enter the session VM". https://code.claude.com/docs/en/sandboxing and https://code.claude.com/docs/en/security | 2025-10-20 (launch) | [doc] |
| **OpenAI Codex:** "By default, the agent runs with network access turned off". Writes go to the workspace only. https://developers.openai.com/codex/agent-approvals-security | current | [search] |
| **GitHub Copilot cloud agent firewall:** egress is limited by default. The firewall does not apply to MCP servers. https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-firewall | current | [search] |
| **Gemini CLI sandbox:** Seatbelt profiles, Docker or Podman, and gVisor `runsc`, which the docs call the "Strongest isolation available". https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/sandbox.md | current | [doc] |
| **Docker Sandboxes:** microVM, deny-by-default egress, "Credential values never enter the VM". https://docs.docker.com/ai/sandboxes/security/ | current | [doc] |
| **Kubernetes agent-sandbox:** "Running Agents on Kubernetes with Agent Sandbox". https://kubernetes.io/blog/2026/03/20/running-agents-on-kubernetes-with-agent-sandbox/ | 2026-03-20 | [doc] (from `kubernetes-agent-sandbox.md`) |

## Sources to cite

- "The lethal trifecta for AI agents: private data, untrusted content, and external communication". Simon Willison. 2025-06-16. https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/ [search]
- "New prompt injection papers: Agents Rule of Two and The Attacker Moves Second". Simon Willison. 2025-11-02. https://simonwillison.net/2025/Nov/2/new-prompt-injection-papers/ [search]
- "Beyond permission prompts: making Claude Code more secure and autonomous". Anthropic Engineering (D. Dworken, O. Weller-Davies). 2025-10-20. https://www.anthropic.com/engineering/claude-code-sandboxing [search]. The post says that sandboxing cut permission prompts by 84% in Anthropic's internal use.
- "Configure the sandboxed Bash tool". Claude Code docs. https://code.claude.com/docs/en/sandboxing [doc]
- "Security". Claude Code docs. https://code.claude.com/docs/en/security [doc]. It recommends VMs "especially when interacting with external web services".
- "Agents Rule of Two: a practical approach to AI agent security". Meta AI. 2025-10-31. URL UNVERIFIED (ai.meta.com was not in the search results).
- "The Attacker Moves Second: Stronger Adaptive Attacks Bypass Defenses Against LLM Jailbreaks and Prompt Injections". Nasr, Carlini, Tramèr et al. 2025-10-10. https://arxiv.org/abs/2510.09023 [search]
- "GitHub MCP Exploited: Accessing private repositories via MCP". Invariant Labs. 2025-05-26. https://invariantlabs.ai/blog/mcp-github-vulnerability [search]
- GHSA-cxm3-wv7p-598c, "Malicious versions of Nx and some supporting plugins were published". Nx. 2025-08-27. https://github.com/nrwl/nx/security/advisories/GHSA-cxm3-wv7p-598c [advisory]
- GHSA-7g7f-ff96-5gcw / CVE-2025-8217, "Malicious script injected into Amazon Q Developer for Visual Studio Code (VS Code) Extension". AWS. 2025-07-26. https://github.com/aws/aws-toolkit-vscode/security/advisories/GHSA-7g7f-ff96-5gcw [advisory]
- "A Mini Shai-Hulud Has Appeared". StepSecurity. 2026-04-29. https://www.stepsecurity.io/blog/a-mini-shai-hulud-has-appeared [search]
- "Supply Chain Compromises Impact Nx Console and GitHub Repositories". CISA. 2026-05-28. https://www.cisa.gov/news-events/alerts/2026/05/28/supply-chain-compromises-impact-nx-console-and-github-repositories [search]
- Claude Code security advisories. Anthropic. https://github.com/anthropics/claude-code/security/advisories [advisory]
- "LLM06:2025 Excessive Agency". OWASP. https://github.com/OWASP/www-project-top-10-for-large-language-model-applications/blob/main/2_0_vulns/LLM06_ExcessiveAgency.md [doc]
- "OWASP Top 10 for Agentic Applications". OWASP GenAI Security Project. 2025-12-09. https://genai.owasp.org/2025/12/09/owasp-top-10-for-agentic-applications-the-benchmark-for-agentic-security-in-the-age-of-autonomous-ai/ [search]
- "Docker Sandboxes: Security". Docker. https://docs.docker.com/ai/sandboxes/security/ [doc]

## Open questions

1. **AWS bulletin number.** Search results say AWS-2025-015. The GHSA text says "While investigating bulletin AWS-2025-016" and links `aws-2025-016`. Open both bulletins on aws.amazon.com before you cite one. UNVERIFIED
2. **Copilot and Cursor CVEs.** I did not verify CVE-2025-53773 (Copilot) or CVE-2025-54135 (Cursor "CurXecute"). One WebSearch call failed, and the GitHub advisory database has no entry for CVE-2025-54135. Leave them out, or check them on the host. UNVERIFIED
3. **AI CLI flags in s1ngularity.** The GHSA does not name the CLIs or their flags. Quote Snyk or StepSecurity for the flags, or open the Nx post-mortem. [search]
4. **How Mini Shai-Hulud got in.** Most write-ups say hijacked npm publisher accounts and an abused OIDC flow. Mend says a hijacked Claude Code GitHub integration. The victim count (1,800+) comes from one source only. UNVERIFIED
5. **Replit primary source.** The primary sources are X posts by Jason Lemkin and Amjad Masad, which I could not fetch. Cite The Register, or check the posts on the host.
6. **Your own MCP route.** `api.githubcopilot.com/mcp` allows `POST` and `DELETE` with no repo path, so the proxy cannot limit MCP writes per repo. Do you want the post to say that the token scope is the control on this path? [inference]
7. **Before you publish,** open each `[search]` URL on the host. The sandbox proxy blocked WebFetch for these hosts.
