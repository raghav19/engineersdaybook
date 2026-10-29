set quiet

# --- Required environment variables ---
gh_token     := env("GH_TOKEN")
claude_token := env("CLAUDE_CODE_OAUTH_TOKEN")
ghcr_token   := env("GITHUB_TOKEN")

ensure-vm:
    {{ source_directory() }}/msb.py ensure-vm
