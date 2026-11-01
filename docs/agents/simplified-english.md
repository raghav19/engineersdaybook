# Simplified Technical English (ASD-STE100)

Apply ASD-STE100 structural rules to every piece of text you produce. This covers two surfaces:

**Agent output** — plans, explanations, PR bodies, commit messages, review comments, status reports.

**Code-level text** — comments, error strings, log messages, docstrings, CLI help text.

## Rules that apply everywhere

- One idea per sentence. Max 20 words for instructions, max 25 words for descriptions.
- Active voice. Name the actor: "The agent deletes the file", not "The file is deleted".
- No phrasal verbs. "Start the job", not "spin up the job". "Remove", not "take off".
- No semicolons. Split into two sentences.
- No synonym rotation. Pick one word for one concept and reuse it. Do not rotate between "check", "verify", and "confirm" for the same action.
- No nominalization. "Analyze the log", not "perform an analysis of the log".
- No marketing adjectives. Delete "seamless", "robust", "powerful", "effortless". State the measurement instead.
- Simple tenses. "The job completed", not "the job has completed". Keep present perfect only when current relevance matters and simple past cannot convey it — flag the departure when you do.

## Rules for agent output (plans, explanations, PR bodies)

- State the claim or the action. Do not stack hedges ("it is important to note that this may potentially help").
- Use a numbered list for any sequence of 3+ steps.
- One topic per paragraph, max 6 sentences.
- When proposing a plan, each step must fit in one sentence. If it does not, split it.

## Rules for code-level text

- Comments: write only when the *why* is not in the code. When you do, use short imperative sentences: "Skip the cache. The file is a symlink."
- Error messages: state what failed, then what to do. "Cannot open config.toml. Check that the file exists in the working directory."
- Log messages: start with the component name, then the action, then the object. "sandbox-boot: mounted /dev/fuse."
- Docstrings: one line for the what. A blank line, then short sentences for the how and why.

## How to apply

Before you finish any change, scan your text for these six habits: synonym rotation, hedge stacking, nominalization, marketing adjectives, run-on sentences, phrasal verbs. Fix each one.

For the full rule set and worked examples, invoke the `/asd-ste100` skill. The skill has two modes — Strict (procedures, error messages) and STE-flavored (prose, PR descriptions). Pick Strict for code-level text and STE-flavored for agent output.

## Boundaries

- Do not simplify past the point of clarity. Removing ambiguity is the goal, not shortest text.
- Do not drop a safety condition, exception, or scope qualifier to shorten a sentence. Flag the trade-off instead.
- Do not promote a hedge to a fact. "May have failed" stays "may have failed", not "failed".
- Technical terms that have no plain-English equivalent (Kustomization, HelmRelease, OCIRepository) stay as-is. Define them once if the reader may not know them.
