# Omarchy Theme

Keeps a regular TTT theme snapshot in sync with the active [Omarchy](https://omarchy.org) palette.

Contributed by [@danielmrdev](https://github.com/danielmrdev).

TTT reads static themes from `{config}/themes/<name>.json`. This plugin converts Omarchy's active palette into that format and writes it as `omarchy.json`, so the Omarchy look becomes an ordinary TTT theme instead of requiring host-side Omarchy support.

## How it works

- Reads `~/.local/state/omarchy/current/theme/colors.toml` every two seconds.
- Merges VS Code token rules from the sibling `vscode-theme.json` when that file exists; a missing or invalid token file falls back to the palette alone.
- Writes a complete snapshot to `{config}/themes/omarchy.json` (`~/.config/ttt/themes/omarchy.json` by default) only when the source content changes.
- Runs `settings.reload` after a successful write, and only while the `theme` setting is exactly `omarchy` — the plugin never switches the selected theme.
- A missing, unreadable, or invalid palette is non-fatal: the previous snapshot is left untouched, and the reason is logged to the output panel and shown once in the status bar.
- The snapshot is never deleted, so it keeps working if Omarchy disappears or the plugin is disabled or uninstalled.

## Requirements

- A TTT build with scoped `fs.read` / `fs.write` manifest paths ([eugenioenko/ttt#908](https://github.com/eugenioenko/ttt/pull/908)). On a build where those permissions are plain booleans the manifest cannot be parsed and TTT skips the plugin — the Plugins panel can still list it as installed, with `--debug` writing the reason to `{config}/ttt.log`.
- The `{config}/themes` directory has to exist. The plugin filesystem API cannot create directories, and refuses to open a missing root:

  ```sh
  mkdir -p ~/.config/ttt/themes
  ```

- `commands: true`, because TTT exposes `ttt.exec_command` — used here only for `settings.reload` — through that permission alone.
- The snapshot is a plain theme file named `omarchy`. A host build that provides its own built-in `omarchy` theme would take precedence over the file whenever it reloads.

## Install

TTT installs plugins from a repository root. This repository is a monorepo, so `omarchy-theme` can only be installed from the plugin panel once it is listed in the [community registry](https://github.com/eugenioenko/ttt/blob/main/community-plugins.json) with a `path` entry. Until then, install it by hand:

```sh
mkdir -p ~/.config/ttt/plugins ~/.config/ttt/themes
cp -a omarchy-theme ~/.config/ttt/plugins/
```

Restart TTT and approve the permission prompt. Selecting the theme stays a manual step — run **Switch Theme** from the command palette and pick **Omarchy**.

## Verifying it works

- `~/.config/ttt/themes/omarchy.json` appears within a couple of seconds of TTT starting.
- A successful sync stays silent. On failure the output panel shows `[omarchy-theme] Omarchy theme: …` and the same text appears in the status bar.
- Run `omarchy-theme-set <name>`: the snapshot is rewritten within two seconds, and an editor with the `omarchy` theme selected recolors.

If nothing happens, run TTT with `--debug` and check `{config}/ttt.log`: a plugin that never loaded leaves a `skip plugin` warning there, while a plugin that loaded but could not write explains itself in the output panel and status bar.

## Permissions

Manifest scopes are intentionally narrow except for the command capability TTT's API requires:

```json
{
  "fs.read": ["~/.local/state/omarchy"],
  "fs.write": ["{config}/themes"],
  "settings": true,
  "settings_keys": ["theme"],
  "commands": true
}
```

The plugin reads only `settings.theme` and never writes settings. It reads only inside the Omarchy state directory, and its only write target is the themes directory. `commands: true` is broad — it also grants command registration and clipboard access — but TTT offers no narrower way to reach `settings.reload`; this plugin calls `ttt.exec_command` for that one command.

## Write behavior

The snapshot is built in memory and written with a single scoped filesystem write. That write is not atomic, so a failure can truncate or damage an existing snapshot rather than leaving the old file intact. The plugin retries on the next poll and never removes the snapshot.

Empty style groups (for example `button.focused`, `syntax.bold`, `fileIcons.red`) are omitted from the snapshot rather than written as `[]`, because TTT decodes those keys into structs and every empty Lua table encodes as an array. The host rejects the whole file with `cannot unmarshal array into Go struct field ... of type config.StyleDef` and stops reading there, so an omitted key — which keeps TTT's own default — is both safer and equivalent.
