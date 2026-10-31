# The editor for the msb sandbox: TTT

Question: Can TTT replace Fresh in the msb sandbox? The VM has no display server, 3 GB of memory, no swap, and an egress allow list. The editor must run the same language servers, and it must work over `ssh -t` into `foot`.

Source: the source and the docs of `eugenioenko/ttt`, read on 2026-10-31. The version is `v1.10.0`, released 2026-10-30, at commit `ea56091bc5d7d9cb8ea2ef7aa8363dc3b12b6042`. The docs are the Markdown files under `docs-web/src/content/docs/` and the site `tttedit.dev`. The terminal library is the pinned dependency `github.com/gdamore/tcell/v3.4.1`. Section 13 records what we ran on the host. Nothing was run in the VM. This note replaces the verdict of `vm-editor-options.md`, which was correct on 2026-10-29.

Evidence tags: **source** means the code says it, and the path follows. **documented** means the docs say it. **measured** means we ran it on 2026-10-31. **inferred** means we drew the conclusion and no source states it.

## Verdict

1. Use TTT. It runs in the VM, it has menus, tabs, a sidebar, a bottom panel, an integrated terminal and the mouse, and it has no modes.
2. Three faults of Fresh have no analogue in TTT. The clipboard never touches X11. No memory limit is set on a language server. There is no workspace trust gate.
3. TTT gives git commit, push, pull and sync in the UI. Fresh gave none of them.
4. Six things are lost. One language server per file extension. No split editor. No `Ctrl+Shift+<letter>` binding. No agent session hub and no orchestrator. No trust gate, which changes the threat model. And no editor support for a `justfile`, because TTT has no Just grammar and we chose not to vendor one.
5. Two risks need a measurement in the VM before we trust them. A flat timeout of 10 seconds covers every request, including `initialize`. And no handler restores the terminal after SIGTERM.
6. The install path works, and we ran it. mise fetched the bare binary, verified it, and named the shim `ttt`. TTT then started against our own `settings.json` with no complaint. Section 13.

## 1. The version and the install

| Claim | Tag | Source |
|---|---|---|
| The release publishes one bare binary per platform. `ttt-linux-amd64` is 16,961,720 bytes, and its sha256 is `0e9344c396a783eaf4fc60f1d6f76b85de2b2c303bba2cb07e563a09950097a0`. A `checksums.txt` asset sits beside it. | source | the GitHub releases API for `v1.10.0` |
| The license is MIT. | documented | the repository |
| The aqua registry has no entry for it. | source | `aquaproj/aqua-registry`, `pkgs/eugenioenko/ttt/pkg.yaml` returns 404 |
| The mise `github:` backend pins an exact version, selects an asset by pattern and renames the executable. It also verifies the digest that GitHub reports, or a checksum file in the same release. | documented | `mise.jdx.dev/dev-tools/backends/github.html` |
| `tools/lsp.toml` already uses that backend for `github:docker/docker-language-server`, and `tools/infra.toml` already uses the table form with `asset_pattern` and `filter_bins`. | source | this repo |
| So the editor needs no Dockerfile stage of its own. One line in `tools/dev.toml` replaces the `curl`, `sha256sum` and `tar` steps that Fresh needed. | inferred | |

The other `github:` entries in this repo download archives. TTT publishes a bare binary. Section 13 records the test of that combination on the host.

## 2. How TTT finds a language server for a file

This is the part that constrains the config. `ResolveLanguage` tries two routes, and it takes the first hit.

```go
func (m *Manager) ResolveLanguage(filePath, languageName string) (serverKey, languageID string, ok bool) {
	ext := strings.ToLower(filepath.Ext(filePath))
	for name, cfg := range m.config.Servers {
		if langID, found := cfg.Languages[ext]; found {
			return name, langID, true
		}
	}
	key := strings.ToLower(languageName)
	if _, found := m.config.Servers[key]; found {
		return key, key, true
	}
	return "", "", false
}
```

**source** `internal/lsp/manager.go`

Four consequences follow, and each one is **source** unless it says otherwise.

| Consequence | Why |
|---|---|
| One server per extension. Two entries that both claim `.py` give a random winner, per lookup. | `for name, cfg := range` over a map, with an early `return`. Go does not order a map. |
| The caller is single valued too, so the data model cannot hold two clients for one file. | `internal/app/app_lsp.go`, `lspResolve` returns one `serverKey`, and `Manager.servers` is `map[string]*Client` |
| `languages` is keyed by extension only. An exact filename key never matches. | the lookup is `cfg.Languages[ext]` |
| A key of `""` would claim every file with no dot in its name. | `filepath.Ext` returns `""` for `LICENSE`, `Makefile`, `justfile` and `Dockerfile` alike |

The second route is the way to reach a file with no extension. It lowercases the language name and uses it as a server key. That name is the display name of the grammar, not its id.

```go
func refFromInfo(info grammars.GrammarInfo) grammarRef {
	return grammarRef{scopeName: info.ScopeName, language: info.DisplayName, languageID: info.ID}
}
```

**source** `internal/highlight/external.go`. For Docker, `textmate-go` declares `ID: "docker"` and `DisplayName: "Dockerfile"`, so the server key must be `dockerfile`. **source** `github.com/eugenioenko/textmate-go/grammars/generated.go`.

Every server key must also be lower case. `ClientForLanguage` does `key := strings.ToLower(lang)` before a case sensitive map lookup, and `normalizeSettings` does not touch `lsp.servers`. A key written `"Dockerfile"` resolves and then never starts, with no error. **source** `internal/lsp/manager.go`, `internal/config/settings.go`

The map value is not a label. It is the `languageId` on the wire, in `client.DidOpen(FileURI(path), langID, text)`. So it must be the id that the server expects, not the name that TTT uses. `.tfvars` needs `terraform-vars`, and `.sh` needs `shellscript`. **source** `internal/app/app_lsp.go`

### Just

`textmate-go` compiles in 125 grammars and Just is not one of them. The extensionless allowlist in TTT does not name it either.

```go
var extraFilenames = map[string]string{
	"gemfile": "ruby", "rakefile": "ruby", "guardfile": "ruby", "podfile": "ruby",
	"vagrantfile": "ruby", "brewfile": "ruby", "jenkinsfile": "groovy",
}
```

**source** `internal/highlight/highlighter.go`. With no grammar, `New()` returns nil, so there is no language name for the second route to use.

TTT can take an external grammar through settings, with no plugin.

```go
type GrammarSetting struct {
	Path string `json:"path"`
	Language string `json:"language,omitempty"`
	FileTypes []string `json:"fileTypes,omitempty"`
	Plugin string `json:"plugin,omitempty"`
}
```

**source** `internal/config/settings.go`. `external.go` prefers the declared `Language` over the name in the grammar, and `externalForFilename` matches the whole lowercased basename before any extension. So one grammar file, one `editor.grammars` entry with `language` set to `justfile`, and a server key named `justfile` close the loop. **source** `internal/highlight/external.go`

The grammar comes from `eugenioenko/ttt-plugins`, path `lang-just/syntaxes/just.tmLanguage.json`, at commit `2722887bdbd6080e1a8970fcdf4cb958b2089484`. It is 18,330 bytes, its scope is `source.just`, and it is MIT, copyright 2024 Robert Neff, taken there from `nefrob/vscode-just`. We declare it through settings rather than install the plugin. The plugin would need the plugin system, an approval dialog and a `git clone` at first run.

**We do not carry it.** This sandbox ships no grammar and no `justfile` server. A `justfile` opens as plain text, and `just-lsp` is out of `tools/lsp.toml`, because nothing could start it without the grammar. The cost is live diagnostics and highlighting in two files, one of them about 350 lines. `just` itself still reports a bad recipe when you run it. The alternative was one vendored file of 18 KB, its MIT notice, and three coordinated settings entries. The mechanism above stays recorded for two reasons. The choice is reversible with one file, and nobody should have to derive the two-route rule again.

The durable answer is upstream. The gap is in the 125 entry table of `textmate-go`, and the same author already ships the grammar in `ttt-plugins/lang-just`. If Just joined that table, a later TTT would handle a `justfile` with no config at all.

## 3. How TTT starts a language server

```go
func NewClient(command []string, workDir string, hooks ClientHooks) (*Client, error) {
	if len(command) == 0 {
		return nil, fmt.Errorf("empty command")
	}
	cmd := exec.Command(command[0], command[1:]...)
	cmd.Dir = workDir
```

**source** `internal/lsp/client.go`. That is the whole spawn path. There is no `cmd.Env`, no `SysProcAttr` and no `setrlimit`. The child inherits the environment of TTT unchanged, and nothing caps its memory or its CPU. Fresh capped each server at 50% of system memory, and that cap killed `marksman` and `bash-language-server`. TTT has no equivalent, so neither server needs an exception.

The replacement risk is a timeout.

```go
var requestTimeout = 10 * time.Second
var errRequestTimeout = errors.New("lsp request timeout")
```

**source** `internal/lsp/client.go`. It is a package level variable and no setting reads it. `Initialize` goes through it. On a miss, `manager.go` sets the state to `ServerFailed` and does not retry. `lsp.restartServer` exists as a manual command. A cold .NET runtime for `marksman`, and a WASM tree-sitter load for `bash-language-server`, are the two candidates on 4 CPUs. **inferred** that they are the candidates, **source** for the mechanism.

One gate runs before the spawn. `exec.LookPath(serverCfg.Command[0])` must succeed, or the server is never attempted and the user sees a status bar toast. **source** `internal/app/app_lsp.go`

## 4. The clipboard

Fresh tried the X11 clipboard at start and stalled for 47 seconds. TTT cannot.

```go
func writeSystemClipboard(s string) {
	if oscWriter != nil {
		encoded := base64.StdEncoding.EncodeToString([]byte(s))
		fmt.Fprintf(oscWriter, "\033]52;c;%s\a", encoded)
	}
	if name, args := findCopyCmd(); name != "" {
		c := exec.Command(name, args...)
		c.Stdin = strings.NewReader(s)
		c.Run()
	}
}
```

**source** `internal/core/clipboard/clipboard.go`. `findCopyCmd` checks `WAYLAND_DISPLAY` and `DISPLAY` before any `LookPath`, and returns empty when both are unset. So in the VM it returns at once, and the copy is an OSC 52 write to the tty. `readSystemClipboard` is symmetric and returns empty. The error of `c.Run()` is discarded, so there is no timeout, no retry and no dialog.

`cmd/ttt/main.go` wires the writer to the tty, not to stderr.

```go
	if tty, ok := screen.Tty(); ok {
		clipboard.SetOSCWriter(tty)
	}
```

There is no clipboard setting. `internal/config/settings.go` has no clipboard section at all. **source** The only levers are the two display variables and `--exec`, which calls `clipboard.DisableSystem()`.

Two consequences. Copy to the host clipboard works if `foot` honors OSC 52, which needs `clipboard-control` in `foot.ini`. **inferred** Paste of host text does not work, because `Get()` returns only what TTT itself copied. And `terminal.ctrlVPastes` defaults to `true`, so `Ctrl+V` in a focused terminal inserts that internal buffer. **documented** `reference/settings.md`

## 5. The keyboard

TTT asks tcell for a bare screen.

```go
func NewTcellScreen() (*TcellScreen, error) {
	s, err := tcell.NewScreen()
```

**source** `internal/term/tcell_screen.go`. With no options, `advancedKeys` in tcell stays false. tcell then negotiates the kitty protocol and enables flag 1 only.

```go
	enableKittyKbd = "\x1b[=1u"     // Technically this pushes
	enableKittyKbdAdv = "\x1b[=15u" // disambiguation, events, alternate keys, all keys
```

**source** tcell v3.4.1, `tscreen.go`. Not 15. So no event type reporting, no alternate keys, and no all keys as escape codes.

That one omission makes `Ctrl+Shift+<letter>` unbindable. Registration folds it to a control key.

```go
	if combo.Ctrl && combo.Rune >= 'a' && combo.Rune <= 'z' {
		key := tcell.KeyCtrlA + tcell.Key(combo.Rune-'a')
		return key, mod, 0
	}
```

**source** `internal/app/keys.go`. So `ctrl+shift+p` registers as `KeyCtrlP` with `ModCtrl|ModShift`. The terminal reports `CSI 112;6u`, tcell has no entry for 112 in `csiUKeys`, and it delivers `KeyRune "p"` with `ModShift|ModCtrl`. The legacy fold that would have caught this checks for exact equality on `ModCtrl`, and Shift defeats it.

```go
		if mod == ModCtrl && !advanced {
			} else if ch >= 'a' && ch <= 'z' { // lower case
				k = KeyCtrlA + Key(ch-'a')
```

**source** tcell v3.4.1, `input.go`. `matchKey` then compares `KeyRune` against `KeyCtrlP` and fails. **source** `internal/ui/root.go`

The upstream keymap avoids the trap by construction. `DefaultKeybindings()` contains zero `ctrl+shift+<letter>` entries, and every `ctrl+shift+*` default uses a named key such as `home`, `end`, `left` or `right`. **source** `internal/config/keybindings.go`

What does work, and what does not.

| Key | Result | Tag |
|---|---|---|
| `ctrl+p` and every plain `ctrl+<letter>` | works in both modes | source |
| `` ctrl+` `` | works in both modes. `comboToTcell` maps it to `KeyNUL`, and `foldCtrlEvent` maps both encodings onto it | source |
| `ctrl+tab` | works only with the kitty protocol negotiated. `foot` negotiates it | source, inferred for `foot` |
| `ctrl+shift+tab` | broken. tcell rewrites it to `KeyBacktab` because `advanced` is false | source |
| `ctrl+shift+p`, `ctrl+shift+f`, `ctrl+shift+g`, `ctrl+shift+e`, `ctrl+shift+k` | broken, all by the mechanism above | source |
| `ctrl+shift+<arrow>`, `ctrl+shift+home`, `alt+shift+up` | work, because they are named keys | source |

The parser itself accepts all of these strings. It splits a chord on whitespace and a step on `+`, it lowercases the input first, and it knows `ctrl`, `alt` and `shift`. So a dead binding loads without a complaint. **source** `internal/config/keybindings.go`, `ParseKeyString`

A one line upstream change would remove the cause. Pass `tcell.OptAdvancedKeys(true)` in `NewTcellScreen()`. It is not a flag flip, because that changes ctrl-letter delivery to `KeyRune` with `ModCtrl` everywhere, and `comboToTcell` and `foldCtrlEvent` would both need work. **inferred**

### Negotiation cost and cleanup

An unsupported terminal costs at most one second.

```go
	expire := time.After(time.Second)
```

**source** tcell v3.4.1, `processInitQ`. No warning, no log line and no refusal to start. `TCELL_NEGOTIATE=disable` skips the queries, and `TCELL_KEYBOARD_PROTOCOL` forces the outcome.

Normal exit and a Go panic both restore the terminal, through `screen.Fini()` and `handlePanic`. **source** `cmd/ttt/main.go`, tcell `disengageFinish`. SIGTERM, SIGINT and SIGHUP are not handled. Neither `tscreen_unix.go` nor `main.go` calls `signal.Notify`, and Go defers do not run on SIGTERM. Because tcell sets the mode rather than pushes it, a killed TTT leaves the terminal in kitty flag 1 for whatever runs next. **source** for the absence, **inferred** for the resulting terminal state.

Mouse and paste are on unconditionally, with `s.EnableMouse()` and `s.EnablePaste()`. That is SGR 1006 and modes 1000, 1002, 1003 and 2004. `TCELL_MOUSE=disable` turns the mouse off. **source** `internal/term/tcell_screen.go`, tcell `vt/mode.go`

### Force keys

```go
var ForceKeyCommands = map[string]bool{
	"terminal.toggle": true, "terminal.fullscreen": true, "editor.quit": true,
	"command.palette": true, "file.quickOpen": true, "sidebar.toggle": true,
	"focus.nextGroup": true, "focus.prevGroup": true,
}
```

**source** `internal/config/keybindings.go`. The set of commands is hardcoded, with no setting and no variable. But `BindKeys` adds a force key only in the non chord branch. So a command moved to a chord stops being forced, and an empty key string drops the binding. **source** `internal/app/commands.go`

The docs list `Ctrl+K P` as a force key. The code says otherwise, because `file.quickOpen` is bound to a chord and chords never reach `AddForceKey`. **source**, and it contradicts `guides/terminal.md`.

## 6. Color

TTT does nothing itself. It calls `tcell.NewScreen()`, and tcell gates 24 bit color on `COLORTERM`.

```go
		} else if slices.Contains([]string{"truecolor", "direct", "24bit"}, cterm) || strings.HasSuffix(nterm, "-direct") || strings.HasSuffix(nterm, "-truecolor") {
			t.truecolor = true
```

**source** tcell v3.4.1, `tscreen.go`. `TERM=foot` has neither suffix, so `COLORTERM=truecolor` must be in the environment. The final `else` sets 256 colors and leaves `truecolor` false. This is the same requirement Fresh had, and the `edit` recipe already sets it. `NO_COLOR` and `TCELL_TRUECOLOR=disable` are the escape hatches.

## 7. Config, themes and grammars

```go
func configPaths() []string {
	if OverrideConfigDir != "" {
		return []string{OverrideConfigDir}
	}
	var paths []string
	if exe, err := os.Executable(); err == nil {
		paths = append(paths, filepath.Join(filepath.Dir(exe), "config"))
	}
	if home, err := os.UserHomeDir(); err == nil {
		paths = append(paths, filepath.Join(home, ".config", "ttt"))
	}
	return paths
}
```

**source** `internal/config/config.go`. Two paths, first file found wins per filename, and no merge across them. `XDG_CONFIG_HOME` is not read. `TTT_CONFIG_DIR` overrides both and becomes the only path, which `cmd/ttt/main.go` sets.

The first path comes from `os.Executable()`, so it is the real binary and not the mise shim. A mise install has no `config/` beside it, so the home path wins today. `TTT_CONFIG_DIR` in `dev-tools/mise.toml` makes that permanent instead of lucky. **inferred**

The config directory must be writable. TTT creates it with `os.MkdirAll` and then writes `state.json`, `settings.json`, `keybindings.json`, `plugins.ttt.json`, `grammars/` and `state/plugins/` into it. With `--debug` it also writes `ttt.log`, and on a panic `crash.log`. **source** `internal/config/config.go`, `internal/config/state.go`

### Themes

The binary carries 19 themes, not 78.

```go
package themes

import "embed"

//go:embed *.json
var FS embed.FS
```

**source** `internal/config/themes/embed.go`. That directory holds `aurora`, `bubblegum`, `default-dark`, `default-light`, `dracula`, `high-contrast-dark`, `high-contrast-light`, `hotline`, `monokai`, `nord`, `one-dark`, `rainy-day-dark`, `rainy-day`, `solarized-dark`, `solarized-light`, `turbo-vision`, `virtru-dark`, `vscode-dark-plus` and `zenith`. The 78 numbered themes live in `config/themes/` in the repository only. `guides/extra-themes.md` says they "are not bundled in the binary but are available in the repository for download". Resolution tries the two config paths and then the embedded set. **source** `internal/config/config.go`, `readFirstTheme`

So a bare binary from mise gives 19 themes. This sandbox uses none of them by name. It sets `theme` to `omarchy`, and the `omarchy-theme` plugin writes `themes/omarchy.json` at each start from the palette of the host. To add one of the 78 or one of the 19 as a file instead, drop its JSON into `~/.config/ttt/themes/` with one COPY line. No clone of the upstream repository is needed.

Theme colors are `"#rrggbb"` hex, and ANSI names are accepted only in `editor.bracketColors`. An empty string means the color of the terminal. `tokenColors` in VS Code format overrides the whole `syntax` mapping if it is present. **documented** `guides/themes.md`

The palette of the host is Fireside, and Omarchy generates a VS Code theme from it at `~/.local/state/omarchy/current/theme/vscode-theme.json`. That file holds 81 `tokenColors` entries in the same shape that TTT accepts, plus 664 named colors. The plugin merges those token rules into the snapshot it writes. We measured the palette against its own background `#0a1220`. Body text `#f0f2f5` is 16.71 to 1. Every syntax color is 5.72 to 1 or above. The one weak color is `#5a606b`, which the palette uses for comments, for muted text and for line numbers, at 2.96 to 1. That is below the 4.5 to 1 of WCAG AA. We kept it. Fireside authors it that way, its own README calls it a low-contrast theme, and the rest of the desktop renders the same value. **measured**, in the sense that we computed the ratios from the palette. We did not read them on a screen.

Two properties of the source palette matter if anyone converts it by hand instead of letting the plugin do it. The VS Code colors carry alpha, and TTT wants `"#rrggbb"`, so a value such as `#88988920` must be flattened onto the background. Flattened at the source alpha, the three `diff` backgrounds land 1.01 to 1.04 to 1 apart, which looks like the defect the Solitude theme had. It is not. TTT's own `nord` is the same. Two of its three diff backgrounds are 1.06 to 1 apart, and its added background sits 1.05 to 1 from the editor background. Subtle diff backgrounds are the house style here, and the solid gutter marks carry the signal, at 5.72 to 7.01 to 1 in this palette. One source value is genuinely broken. `editor.lineHighlightBackground` is `#0a122060`, which flattens to the background itself, so a direct copy would leave the active line invisible. The plugin mixes its own values instead of copying these (`mix(background, green, diff_blend)`). So this is a warning about the source, not a defect we ship. What the plugin does for the active line is not verified. **measured** for the ratios, **source** for the mix call.

`vscode-dark-plus` was the fallback while the palette route was open. Its comments are 5.00 to 1 and its body text is 11.25 to 1, so it needs no patch. It stays one keystroke away, because the binary carries it.

The first candidate was `29-slate`, one of the 78. It sets `default.fg` to `#b0b8c4` on `#1a1e24`, and its diff colors are distinct too. But `syntax.comment.fg` and `muted.fg` are both `#555e6a`, which is 2.55 to 1 against that background. The Solitude theme for Fresh had the same defect at 2.2 to 1, and we raised it to 5.9 to 1. `#8b9296` would give 5.30 to 1 there, but that means a patched copy of an upstream file, and it would drift. We dropped the candidate. **source** for the values, **measured** for the ratios.

### Images and diagrams

TTT has no way to draw a picture in this sandbox. Its whole image support is one setting.

```go
const (
	ImageProtocolAuto  = "auto"
	ImageProtocolKitty = "kitty"
	ImageProtocolNone  = "none"
)

type ImageSettings struct {
	Protocol string `json:"protocol"`
}
```

**source** `internal/config/settings.go`. There is no sixel and no iterm2, and `normalizeSettings` rejects any other value. The host terminal is `foot` 1.28.0, which supports sixel and whose README never mentions the Kitty graphics protocol. **documented** for foot, **measured** for the version. So the two do not meet, and a fenced `mermaid` block renders as highlighted source.

Rendering one would need a second thing anyway: a mermaid renderer. `@mermaid-js/mermaid-cli` pulls Node, Puppeteer and Chromium, and Chromium needs Xvfb plus new hosts in `network.allow`. The published settings reference does not mention images at all, which is how the `Image` struct was missed at first. **source** for the struct, **documented** for the absence in the reference.

### Keybindings

The user file merges over the defaults per command, and it does not replace the whole map.

```go
func MergeKeybindings(defaults, overrides []KeyBinding) []KeyBinding {
	overridden := make(map[string]bool)
	for _, kb := range overrides {
		overridden[kb.Command] = true
	}
	...
	for _, kb := range defaults {
		if !overridden[kb.Command] {
			merged = append(merged, kb)
		}
	}
```

**source** `internal/config/keybindings.go`. An override drops every default key of that command. A displaced default keeps its own key. Overrides come first in the slice, and dispatch is first match wins, so an override wins a collision. **source** `internal/ui/root.go`

The struct is the whole schema.

```go
type KeyBinding struct {
	Key string `json:"key"`
	Command string `json:"command"`
	Steps []KeyCombo `json:"-"`
}
```

There is no `args`, no `when` and no `context`. `encoding/json` drops unknown fields, so a VS Code style `when` clause is discarded and not honored. The dict form is preferred and the array form is a fallback. An empty string, or an empty array, unbinds, which is what the Clear button writes. **source** `internal/config/keybindings.go`, `LoadKeybindings`, `SaveKeybindings`

Errors are silent. `ParseKeyBindings` returns a first error and `cmd/ttt/main.go` discards it. A malformed key has no `Steps`, and `BindKeys` skips it. An unknown command id passes load and merge, and then `Registry.Execute` returns false at press time. **source** `internal/command/registry.go`

## 8. Plugins and the network

Nothing is bundled. Discovery is `os.ReadDir` over two directories, and there is no `go:embed` in `manager.go`.

```go
	registryPath := config.ConfigFilePath("plugins.ttt.json")
	pluginsDir := filepath.Join(filepath.Dir(registryPath), "plugins")
	localPluginsDir := filepath.Join(editor.Workspace.Primary(), "plugins")
```

**source** `cmd/ttt/main.go`, `internal/plugin/manager.go`. The 25 built-in server configurations are community plugins in `eugenioenko/ttt-plugins`, not embedded Lua. We write `lsp.servers` into settings instead, so no plugin is needed for a language server.

Approval is required only when the registry has no entry for the plugin, or when the declared permissions differ from the registry entry. `LoadAll()` returns the pending list, and an empty list means no dialog. Grants persist to `plugins.ttt.json` as a bare JSON array, which is writable ahead of time. **source** `internal/plugin/manager.go`, `internal/plugin/registry.go`

One caveat on pre-writing grants. An entry whose `GrantsVersion` is below `localAccessGrants` loses its `network.http` permission on load. Both constants are 2:

```go
const (
	localAccessGrants = 2
	grantsVersion     = localAccessGrants
)
```

**source** `internal/plugin/registry.go`. Only `NetworkHTTP` is cleared, so scoped `fs.read` and `fs.write` grants survive a stale version. Writing `"grantsVersion": 2` avoids the question and keeps the file identical to what `Save()` would write, which uses a two space indent.

The one automatic outbound call is a plugin registry fetch.

```go
const DefaultRegistryURL = "https://raw.githubusercontent.com/eugenioenko/ttt/main/community-plugins.json"
	client := &http.Client{Timeout: 10 * time.Second}
```

**source** `internal/plugin/registry_remote.go`. It runs in a goroutine inside `if cfg.Settings.Plugins.IsEnabled()`, so `{"plugins": {"enabled": false}}` removes it, and even a DNS failure cannot block startup. `raw.githubusercontent.com` is covered by `*.githubusercontent.com` in `network.allow`.

There is no update check, no version check and no telemetry in the files we read. `internal/github/github.go` imports no `net/http` at all. It shells out to `gh` for `repo clone`, `pr view`, `pr diff` and `api graphql`, and none of those calls has a timeout. The image has no `gh`, so pull request review does not work. `--listen` opens an HTTP server on `127.0.0.1:4242`, and it is flag gated. The two URLs in `internal/app/about.go` are display strings. **source** **inferred** for the absence claims, because we could not grep the whole tree.

### What this sandbox does

`plugins.enabled` is `true`, and the image vendors no plugin. Both that we use are in the community registry at the pinned commit, each with the `path` entry that an install from a monorepo needs:

```text
markdown-preview   path "markdown-preview"   featured true   version 0.1.0
omarchy-theme      path "omarchy-theme"                      version 0.1.0
```

**source** `community-plugins.json` at commit `ea56091b`, 55 entries. The README of `omarchy-theme` says it "can only be installed from the plugin panel once it is listed in the community registry with a `path` entry". That warning is stale. The entry is there, so the panel installs both, and that is what we do.

An earlier draft of this change vendored both plugins and pre-wrote their grants. It was reverted. The 11 files bought only the removal of two clicks, and they put a copy of upstream Lua in a public repo.

The mechanism still belongs here, because it is how a dialog would be suppressed if that ever mattered. Approval is skipped when `Find(manifest.Name)` succeeds in `~/.config/ttt/plugins.ttt.json` and `DiffPermissions` then reports nothing. `DiffPermissions` flags only a permission that is requested and not granted, so an exact match gives an empty diff. `Find` matches on `Name` alone and ignores `Version`, so an upstream version bump does not re-trigger the dialog. That file is a bare JSON array, and `grantsVersion` should be 2, the value of `localAccessGrants`. A lower value makes `LoadRegistry` clear that entry's `network.http`, and nothing else. **source** `internal/plugin/registry.go`, `internal/plugin/permissions.go`

What each plugin asks for, from its own manifest:

| Plugin | Permissions |
|---|---|
| `markdown-preview` | `panel.editor`, `commands`, `editor.read` |
| `omarchy-theme` | `fs.read ["~/.local/state/omarchy"]`, `fs.write ["{config}/themes"]`, `settings`, `settings_keys ["theme"]`, `commands` |

Neither asks for `system.exec`, `network.http` or `network.rpc`. The scoped `fs` paths need the change in `eugenioenko/ttt#908`, which merged on 2026-10-16 and is in v1.10.0. We read `FsRead FsAccess` in `permissions.go` at the pinned commit. On a build without it the manifest does not parse and TTT skips the plugin. **source** for the manifests and for `permissions.go`, **documented** for #908 in the plugin README.

Two costs follow. Enabling plugins brings the registry fetch above, once per start, to a host that `network.allow` already covers. And an install does not survive `just msb rm`, because `~/.config/ttt` is in the VM and not in a volume.

## 9. Trust

There is no gate. We read `internal/config/settings.go`, `internal/config/state.go`, `internal/lsp/manager.go`, `internal/lsp/client.go`, `internal/app/app_lsp.go`, `internal/plugin/manager.go`, `reference/keybindings.md` and `guides/plugins.md` for the word, and it does not appear. **source** for the absence in those files. `state.go` is the whole persisted schema, and its closest field is `RecentFolders`.

A server starts when a matching file opens, with no check beyond `lsp.enabled` and `LookPath`. So `sandbox-boot` writes no trust file, and we removed the step that wrote one for Fresh.

The cost is a change to the threat model. Opening a hostile repository runs the configured `lsp.servers` and `formatters` at once, with `cmd.Dir` set to that repository. Our config is baked into the image, so the blast radius is what we configured. A repository local `plugins/` directory is scanned, but a plugin there still needs approval before it runs. **source** `cmd/ttt/main.go`, `internal/plugin/manager.go`

## 10. The terminal

`terminal.shell` is used verbatim as the executable name. It is not split into argv and not passed to `/bin/sh -c`, so `"/bin/bash --login -i"` would fail with "executable file not found". The struct has an `Args` field that the published settings reference omits.

```go
type TerminalSettings struct {
	Shell string `json:"shell,omitempty"`
	Args []string `json:"args,omitempty"`
	...
}
```

**source** `internal/config/settings.go`. The spawn is `pt.Command(shell, args...)`, and the environment is `os.Environ()` plus the caller's entries plus `TERM=xterm-256color` last. So `TERM` always wins, whatever `foot` exported, and `COLORTERM` is inherited. **source** `internal/terminal/terminal.go`

Focus passes every key to the PTY except the force keys, and chord prefixes go to the program too. **source** `internal/ui/root.go` Scrollback defaults to 1000 lines, the wheel moves 3 lines, `Shift+PgUp` and `Shift+PgDn` move half a page, and any keypress snaps back to the live view. **documented** `guides/terminal.md`

## 11. The CLI surface

The parser is hand rolled, with no `flag` and no cobra. **source** `cmd/ttt/main.go`

| Flag | Use here |
|---|---|
| `--version`, `-v` | the build time check in the Dockerfile |
| `--exec "commands"` | a headless run against a simulation screen. The docs say it exits nonzero on a failed action, and that `wait-for TEXT [timeout=MS]` synchronizes. Section 13: it hung with no tty |
| `--config <file>` | overrides the settings file only, not the directory |
| `--debug` | writes `~/.config/ttt/ttt.log` |
| `--listen` | an HTTP command server on `127.0.0.1:4242` |
| `--new-window` | ignores `reuseWindow` |
| positional `.` | opens the current directory, which is what `edit` passes |
| positional PR URL | opens a pull request for review, and needs `gh` |

`TTT_CONFIG_DIR` is an environment variable and not a flag. `--welcome` and `--workspace` appear in the help text but `parseFlags()` does not handle them, so they are presumably consumed inside `app.BuildApp`, which we did not read. **source** for the flag list, **inferred** for those two.

`--exec` should have been the loud check for a silent config error, because unknown command ids and malformed key strings load without a complaint. It hung with no tty, so section 13 records it as unusable in a build step. We ship no `keybindings.json`, which removes most of that exposure. What is left is a check by hand in the VM.

## 12. Agent sessions

There is no equivalent of the Fresh orchestrator, and no session scanner. We read all 61 entries of `community-plugins.json`. The closest is `ttt-mcp`, which points the other way and lets an agent drive a running editor. **source** Nothing matches agent, session, Claude, Codex, worktree or orchestrator, and nothing reads `~/.claude/projects/*.jsonl`.

The orchestration layer in this ecosystem is Herdr, and TTT is the plugin.

```
A [Herdr](https://herdr.dev) plugin for [TTT Editor](https://tttedit.dev). Opens TTT as a first-class pane inside your Herdr workspace.
```

**documented** `herdr-plugin/README.md`, which also lists `ttt.editor.open-worktree`. Herdr is a separate binary from `herdr.dev`, and that host is not in `network.allow`. **source** `sandbox.yaml`

## 13. What we ran on the host

We ran four checks on 2026-10-31, on x86_64 Linux with glibc, outside the VM. All of them used a throwaway `MISE_DATA_DIR` and a throwaway config directory, so nothing in the image or in this repo took part.

| Check | Result | Tag |
|---|---|---|
| `mise install` of the exact entry that `tools/dev.toml` now carries | It downloaded the asset `ttt-linux-amd64`, 17.0 MB, ran a separate checksum step, and installed to `installs/github-eugenioenko-ttt/1.10.0/ttt`. The shim came out named `ttt`, so `rename_exe` worked. 6.2 seconds in total | measured |
| `ttt --version` | It printed `ttt v1.10.0` and returned at once, with no tty and no config directory. So the Dockerfile can check the binary at build time | measured |
| Startup against our own `settings.json` | We pointed `TTT_CONFIG_DIR` at a directory that held our real `ttt-settings.json`, the vendored Just grammar, and `29-slate.json` fetched at the pinned commit. TTT started in debug mode, wrote `state.json`, and reached the `--exec` script. The log has no line about the settings, the theme or the grammar | measured |
| `--exec 'wait-for justfile timeout=4000'` | It blocked for more than 120 seconds and we killed it. The documented `timeout=MS` did not end the wait | measured |

The last line matters. The docs promise that `--exec` "exits nonzero on a failed action". We planned to use it as the loud check for a config error, because unknown keys and unknown command ids load in silence. With no tty it does not return. So the image cannot check the config that way, and the check moves into the VM. **documented** for the promise, **measured** for the hang.

The startup check is weaker than it looks. The log stops at the `exec_script` line. It tells us that TTT read the settings, resolved the theme name and loaded the grammar with no complaint. It does not tell us that the grammar matches a `justfile`, and it does not tell us that any server starts. None of the eight servers was installed on the host.

Three parts of that run no longer match the shipped config. The test used `29-slate`, the vendored Just grammar, and `plugins.enabled` set to `false`. `settings.json` now names the theme `omarchy`, declares no grammar, and turns the plugin system on. So the shipped config exercises paths that the host test did not reach. Those are the plugin loader, an install from the panel, and a theme that a plugin writes at runtime. What still holds is the shape of the test. TTT read a settings file of this kind and started.

## 14. Not tested

Nothing was run in the VM or in a container. Section 13 covers what we ran on the host.

- The eight language servers, and the diagnostics of each.
- Whether `marksman` and `bash-language-server` answer `initialize` inside 10 seconds on 4 CPUs.
- The `dockerfile` entry. It has no `languages` map, so it depends on the second route of `ResolveLanguage` and on the grammar display name being `Dockerfile`. With the Just grammar gone it is the only entry that takes that route, and it is now the least proven part of the config.
- Whether `docker-language-server` gives diagnostics under TTT. It gave none under Fresh, for a reason specific to Fresh.
- The memory of TTT, and the peak of the loaded VM.
- OSC 52 copy through `foot` into the host clipboard, and `clipboard-control` in `foot.ini`.
- Whether TTT releases mouse reporting while the integrated terminal has focus. Mode 1003 reports all motion, so `claude` and `qwen` may lose the mouse.
- The terminal state after SIGTERM.
- The mise install inside the image build. Section 13 tested it on the host, not under `docker buildx build`.
- The mouse in general. We read the code and the docs.
- Whether the panel installs both plugins, and whether `omarchy-theme` then writes `themes/omarchy.json`.
- Whether the agent user can read the mounted palette. The host files are mode 644 and the host folders are 755, so a uid mismatch should still allow a read. That is reasoning and not a test.
- Whether "Preview: Markdown" renders, and what it does with a fenced block.
- Whether the theme follows a switch of the Omarchy theme on the host within two seconds.

## 15. Risks

| Risk | Note |
|---|---|
| The 10 second LSP timeout | Not configurable. A server that misses `initialize` is marked failed and does not retry. Two candidates are named in section 3 |
| No SIGTERM handler | A killed TTT can leave the terminal in kitty flag 1. `TCELL_KEYBOARD_PROTOCOL=legacy` avoids it and costs `ctrl+tab` |
| One server per extension | A future need for `ty` and `ruff` together has no config answer. It needs an upstream change |
| No `justfile` support | A `justfile` opens as plain text and no server runs for it. Reversible with one vendored grammar, or by an upstream change to `textmate-go`. Section 2 |
| No split editor | Permanent. It is not a missing binding, the concept does not exist |
| `Ctrl+Shift+<letter>` | Permanent until upstream passes `OptAdvancedKeys(true)`. Any future VS Code style keymap hits this wall |
| Silent config errors | Unknown keys and unknown command ids load without a complaint. `ttt --exec` hung with no tty, so no automatic check exists. Section 13 |
| Version 1.10.0 | The settings schema is versioned by a `version` field, so it can change. The `Args` field is already absent from the published reference |
| The theme depends on a host mount | `omarchy.json` is written at runtime from a read-only mount of the host palette. A host with no Omarchy at that path fails the VM creation. If the mount is unreadable at runtime, the plugin leaves the previous snapshot alone and logs the reason to the output panel |
| Two plugins are installed by hand | The install does not survive `just msb rm`, and each one asks for approval. Until `omarchy-theme` runs, the theme `omarchy` does not resolve and TTT falls back to its own default |
| Only 19 themes ship in the binary | The other 78 need a vendored JSON each, and that copy then drifts from upstream |
| No image, so no diagram | `image.protocol` allows `auto`, `kitty` and `none`. `foot` has sixel and not Kitty graphics. Section 7 |
| No trust gate | A change to the threat model, not a bug. Section 9 |
| `TERM` is forced | `xterm-256color` inside the integrated terminal, whatever the host terminal exported |
