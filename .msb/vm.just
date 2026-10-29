set quiet

# --- Required environment variables ---
GH_TOKEN                := env("GH_TOKEN")
CLAUDE_CODE_OAUTH_TOKEN := env("CLAUDE_CODE_OAUTH_TOKEN")
GITHUB_TOKEN            := env("GITHUB_TOKEN")

ensure-vm:
    {{ source_directory() }}/msb.py ensure-vm
