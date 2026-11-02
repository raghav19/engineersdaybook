## Summary

```diff
 .msb/
 ├── image/
 │   ├── Dockerfile
 │   │   └── +COPY herdr-config.toml → /home/agent/.config/herdr/config.toml
 │   └── configs/agents/
 │   │   └── +herdr-config.toml   # omarchy fireside theme
 └── justfile
     └── -herdr recipe            # launch via shell + herdr instead
```

Adds omarchy fireside theme for Herdr. Uses `theme.name = "terminal"` to inherit the host foot palette, with custom UI token overrides for panel, sidebar, accent, and text colours.

Removes the `just msb herdr` recipe — launch Herdr via `just msb shell` then `herdr` directly.

## Evidence

Config file created at `.msb/image/configs/agents/herdr-config.toml`:
```toml
[theme]
name = "terminal"

[theme.custom]
panel_bg = "#0a1220"
sidebar_bg = "#0a1220"
active_row_bg = "#111f37"
accent = "#e48b7a"
text = "#f0f2f5"
```

## Merge Danger

**Door:** two-way

Revert the commit to remove.

**Blast radius:** none

Adds one config file, removes one recipe. No existing behaviour changes.
