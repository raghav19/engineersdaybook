local M = {}

local minimum_contrast_ratio = 4.5
local selection_blend = 0.28
local surface_blend = 0.08
local search_match_blend = 0.35
local diff_blend = 0.18

local DEFAULT = {
  default = { fg = "#fafafa", bg = "#1f1f1f" },
  muted = { fg = "#888888" },
  success = {},
  danger = {},
  warning = {},
  conflict = {},
  statusBar = {},
  commitHeader = {},
  tabs = {
    active = { fg = "#ffffff", bold = true },
    inactive = { fg = "#999999" },
    selected = {},
  },
  sidebar = {
    header = { fg = "#ffffff", bold = true },
    item = {},
    selected = { fg = "#ffffff", bg = "#37373d" },
  },
  dialog = {
    input = {},
    item = {},
    selected = { fg = "#ffffff", bg = "#37373d" },
    muted = {},
  },
  editor = {
    lineNumber = { fg = "#999999" },
    activeLine = { bg = "#282828" },
    selection = { bg = "#282828" },
    searchMatch = { bg = "#623800" },
    searchActive = { bg = "#9e6a03" },
    bracketMatch = { bg = "#3a3a3a" },
    bracketColors = { "yellow", "magenta", "blue" },
    diagnostics = { error = {}, warning = {}, info = {}, hint = {} },
  },
  menu = {
    item = {},
    active = { fg = "#ffffff", bg = "#505050", bold = true },
  },
  input = { item = {}, placeholder = {}, action = {} },
  button = { item = {}, focused = {} },
  hover = { bold = {}, italic = {}, code = {} },
  border = { fg = "#555555" },
  borderActive = {},
  diff = {
    added = {},
    deleted = {},
    modified = {},
    collapsedEmphasis = { bold = true },
    collapsedHover = {},
    collapsed = {},
    gutterAdded = {},
    gutterDeleted = {},
    gutterModified = {},
    gutterBookmark = {},
  },
  scrollbar = { fg = "#999999", bg = "#555555" },
  syntax = {
    comment = { fg = "#6a9955" },
    string = { fg = "#ce9178" },
    keyword = { fg = "#569cd6" },
    number = { fg = "#b5cea8" },
    operator = { fg = "#d4d4d4" },
    ["function"] = { fg = "#dcdcaa" },
    type = { fg = "#4ec9b0" },
    builtin = { fg = "#4ec9b0" },
    variable = { fg = "#9cdcfe" },
    punctuation = { fg = "#d4d4d4" },
    tag = { fg = "#569cd6" },
    attribute = { fg = "#9cdcfe" },
    regexp = {},
    heading = {},
    bold = {},
    italic = {},
    quote = {},
    inserted = {},
    deleted = {},
    invalid = {},
    control = {},
    storage = {},
    constant = {},
    escape = {},
    parameter = {},
    property = {},
    self = {},
    namespace = {},
    decorator = {},
    link = {},
    code = {},
    interpolation = {},
    selector = {},
    readonlyVariable = {},
  },
  fileIcons = {
    red = {}, yellow = {}, green = {}, cyan = {}, blue = {}, magenta = {},
  },
  borders = {
    horizontal = "─",
    vertical = "│",
    topLeft = "╭",
    topRight = "╮",
    bottomLeft = "╰",
    bottomRight = "╯",
    topTee = "┬",
    bottomTee = "┴",
    leftTee = "├",
    rightTee = "┤",
  },
  terminal = {
    black = "#1e1e1e",
    red = "#f44747",
    green = "#6a9955",
    yellow = "#d7ba7d",
    blue = "#569cd6",
    magenta = "#c586c0",
    cyan = "#4ec9b0",
    white = "#d4d4d4",
    brightBlack = "#808080",
    brightRed = "#f14c4c",
    brightGreen = "#73c991",
    brightYellow = "#e2c08d",
    brightBlue = "#6cb6ff",
    brightMagenta = "#d670d6",
    brightCyan = "#58d1c9",
    brightWhite = "#e5e5e5",
  },
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function strip_comment(line)
  local quote, escaped = nil, false
  for index = 1, #line do
    local char = line:sub(index, index)
    if quote == '"' and char == "\\" and not escaped then
      escaped = true
    elseif quote and char == quote and not escaped then
      quote = nil
    elseif not quote and (char == '"' or char == "'") then
      quote = char
    elseif not quote and char == "#" then
      return line:sub(1, index - 1)
    else
      escaped = false
    end
  end
  if quote then return nil end
  return line
end

local function utf8(codepoint)
  if codepoint < 0x80 then return string.char(codepoint) end
  if codepoint < 0x800 then
    return string.char(0xc0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
  end
  if codepoint < 0x10000 then
    return string.char(0xe0 + math.floor(codepoint / 0x1000), 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
  end
  return string.char(0xf0 + math.floor(codepoint / 0x40000), 0x80 + math.floor(codepoint / 0x1000) % 0x40, 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
end

local function parse_string(raw, line_no)
  local quote = raw:sub(1, 1)
  if (quote ~= '"' and quote ~= "'") or raw:sub(-1) ~= quote then
    return nil, "expected string at line " .. line_no
  end

  local body, value = raw:sub(2, -2), {}
  local index = 1
  while index <= #body do
    local char = body:sub(index, index)
    if char == quote then return nil, "invalid string at line " .. line_no end
    if char == "\\" and quote == '"' then
      index = index + 1
      local escaped = body:sub(index, index)
      local replacements = {
        ['"'] = '"', ["\\"] = "\\", b = "\b", t = "\t",
        n = "\n", f = "\f", r = "\r",
      }
      if replacements[escaped] then
        value[#value + 1] = replacements[escaped]
      elseif escaped == "u" or escaped == "U" then
        local digits = escaped == "u" and 4 or 8
        local hex = body:sub(index + 1, index + digits)
        local codepoint = #hex == digits and hex:match("^%x+$") and tonumber(hex, 16) or nil
        if not codepoint or codepoint > 0x10ffff or (codepoint >= 0xd800 and codepoint <= 0xdfff) then
          return nil, "invalid Unicode escape at line " .. line_no
        end
        value[#value + 1] = utf8(codepoint)
        index = index + digits
      else
        return nil, "invalid escape at line " .. line_no
      end
    else
      value[#value + 1] = char
    end
    index = index + 1
  end
  return table.concat(value)
end

local function valid_toml_scalar(value)
  if value == "true" or value == "false" or value == "inf" or value == "+inf" or value == "-inf"
    or value == "nan" or value == "+nan" or value == "-nan" then
    return true
  end

  local number = value:gsub("_", "")
  if number:match("^[+-]?%d+$") or number:match("^0[xX]%x+$")
    or number:match("^0[oO][0-7]+$") or number:match("^0[bB][01]+$") then
    return true
  end
  if number:match("^[+-]?%d+%.%d+$") or number:match("^[+-]?%d+[eE][+-]?%d+$")
    or number:match("^[+-]?%d+%.%d+[eE][+-]?%d+$") then
    return true
  end
  return value:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
    or value:match("^%d%d:%d%d:%d%d") ~= nil
end

local function parse_toml(source)
  local values = {}
  local line_no = 0
  for raw_line in (source .. "\n"):gmatch("(.-)\n") do
    line_no = line_no + 1
    local uncommented = strip_comment(raw_line)
    if not uncommented then return nil, "invalid TOML at line " .. line_no end
    local line = uncommented:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local key, raw = line:match("^([%w_%-]+)%s*=%s*(.-)%s*$")
      if not key or not raw or values[key] ~= nil then
        return nil, "invalid TOML at line " .. line_no
      end
      local quote = raw:sub(1, 1)
      if quote == '"' or quote == "'" then
        local value, err = parse_string(raw, line_no)
        if value == nil then return nil, err end
        values[key] = value
      elseif valid_toml_scalar(raw) then
        values[key] = false
      else
        return nil, "invalid TOML value at line " .. line_no
      end
    end
  end
  return values
end

local function rgb(value)
  if type(value) ~= "string" or not value:match("^#%x%x%x%x%x%x$") then return nil end
  return tonumber(value:sub(2, 3), 16), tonumber(value:sub(4, 5), 16), tonumber(value:sub(6, 7), 16)
end

local function hex(r, g, b)
  return string.format("#%02x%02x%02x", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

local function mix(background, foreground, amount)
  local br, bg, bb = rgb(background)
  local fr, fg, fb = rgb(foreground)
  return hex(br + (fr - br) * amount, bg + (fg - bg) * amount, bb + (fb - bb) * amount)
end

local function luminance(r, g, b)
  local function channel(value)
    value = value / 255
    if value <= 0.04045 then return value / 12.92 end
    return ((value + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

local function contrast(r1, g1, b1, r2, g2, b2)
  local first, second = luminance(r1, g1, b1), luminance(r2, g2, b2)
  if first < second then first, second = second, first end
  return (first + 0.05) / (second + 0.05)
end

local function safe(foreground, background, fallback)
  local r, g, b = rgb(foreground)
  local br, bg, bb = rgb(background)
  if not r then
    foreground = fallback
    r, g, b = rgb(foreground)
  end
  if contrast(r, g, b, br, bg, bb) >= minimum_contrast_ratio then return foreground end

  local target = { 0, 0, 0 }
  if contrast(255, 255, 255, br, bg, bb) > contrast(0, 0, 0, br, bg, bb) then
    target = { 255, 255, 255 }
  end
  for step = 1, 255 do
    local amount = step / 255
    local candidate = hex(
      r + (target[1] - r) * amount,
      g + (target[2] - g) * amount,
      b + (target[3] - b) * amount
    )
    local cr, cg, cb = rgb(candidate)
    if contrast(cr, cg, cb, br, bg, bb) >= minimum_contrast_ratio then return candidate end
  end
  return hex(target[1], target[2], target[3])
end

local function set(style, foreground, background)
  if foreground then style.fg = foreground end
  if background then style.bg = background end
end

local function token_colors(document, background, foreground)
  if type(document) ~= "table" or type(document.tokenColors) ~= "table" then return nil end
  local result = {}
  for _, item in ipairs(document.tokenColors) do
    if type(item) ~= "table" or (item.name ~= nil and type(item.name) ~= "string") then return nil end
    local source = item.settings
    if source ~= nil and type(source) ~= "table" then return nil end
    source = source or {}
    if (source.foreground ~= nil and type(source.foreground) ~= "string")
      or (source.fontStyle ~= nil and type(source.fontStyle) ~= "string") then
      return nil
    end

    local token_settings = {}
    if source.foreground ~= nil then token_settings.foreground = source.foreground end
    if source.fontStyle ~= nil then token_settings.fontStyle = source.fontStyle end
    local output = { settings = token_settings }
    if item.name ~= nil then output.name = item.name end
    if type(item.scope) == "string" then
      local scopes = {}
      for scope in (item.scope .. ","):gmatch("(.-),") do
        local trimmed = scope:match("^%s*(.-)%s*$")
        if trimmed ~= "" then scopes[#scopes + 1] = trimmed end
      end
      if #scopes > 0 then output.scope = scopes end
    elseif type(item.scope) == "table" then
      local scopes = {}
      for _, scope in ipairs(item.scope) do
        if type(scope) ~= "string" then return nil end
        local trimmed = scope:match("^%s*(.-)%s*$")
        if trimmed ~= "" then scopes[#scopes + 1] = trimmed end
      end
      if #scopes > 0 then output.scope = scopes end
    elseif item.scope ~= nil then
      return nil
    end

    local color = output.settings.foreground
    if type(color) == "string" and #color == 9 and color:sub(1, 1) == "#" then
      color = color:sub(1, 7)
    end
    if rgb(color) then output.settings.foreground = safe(color, background, foreground) end
    result[#result + 1] = output
  end
  if #result == 0 then return nil end
  return result
end

-- TTT decodes its style groups into structs, and the Lua bridge encodes every
-- empty table as `[]`, which the host rejects: "cannot unmarshal array into Go
-- struct field ... of type config.StyleDef". An absent key keeps the host
-- default, so empty groups are dropped instead of emitted.
local function drop_empty_groups(value)
  for key, child in pairs(value) do
    if type(child) == "table" then
      drop_empty_groups(child)
      if next(child) == nil then value[key] = nil end
    end
  end
end

function M.convert(source, token_document)
  if type(source) ~= "string" then return nil, "palette must be a string" end
  local values, err = parse_toml(source)
  if not values then return nil, err end

  local function color(...)
    for index = 1, select("#", ...) do
      local value = values[select(index, ...)]
      if rgb(value) then return value:lower() end
    end
  end

  local foreground, background = color("foreground", "fg"), color("background", "bg")
  if not foreground or not background then
    return nil, "Omarchy palette requires valid foreground and background colors"
  end

  local ansi = {}
  for index = 0, 15 do ansi[index] = color("color" .. index) end
  local function at(index, fallback) return ansi[index] or fallback end
  local accent = color("accent") or at(4, foreground)
  local muted = color("muted") or at(8, mix(foreground, background, 0.5))
  local selection = color("selection") or mix(background, accent, selection_blend)
  local surface = color("background1", "surface") or mix(background, foreground, surface_blend)
  local function palette(name, index, fallback) return color(name) or at(index, fallback) end

  local red = palette("red", 1, accent)
  local green = palette("green", 2, accent)
  local yellow = palette("yellow", 3, accent)
  local blue = palette("blue", 4, accent)
  local magenta = palette("magenta", 5, accent)
  local cyan = palette("cyan", 6, accent)
  local bright_red = palette("bright_red", 9, red)
  local bright_green = palette("bright_green", 10, green)
  local bright_yellow = palette("bright_yellow", 11, yellow)
  local bright_blue = palette("bright_blue", 12, blue)
  local bright_magenta = palette("bright_magenta", 13, magenta)
  local bright_cyan = palette("bright_cyan", 14, cyan)
  local bright_white = palette("bright_white", 15, foreground)
  local theme = copy(DEFAULT)

  set(theme.default, foreground, background)
  set(theme.muted, muted)
  set(theme.success, green)
  set(theme.danger, red)
  set(theme.warning, yellow)
  set(theme.conflict, magenta)
  set(theme.statusBar, foreground, surface)
  set(theme.tabs.active, accent)
  set(theme.tabs.inactive, muted)
  set(theme.tabs.selected, foreground, selection)
  set(theme.sidebar.header, accent)
  set(theme.sidebar.item, foreground)
  set(theme.sidebar.selected, foreground, selection)
  set(theme.dialog.selected, foreground, selection)
  set(theme.dialog.muted, muted)
  set(theme.menu.item, foreground)
  set(theme.menu.active, foreground, selection)
  set(theme.border, muted)
  set(theme.borderActive, accent)
  set(theme.editor.lineNumber, muted)
  set(theme.editor.activeLine, nil, surface)
  set(theme.editor.selection, nil, selection)
  set(theme.editor.searchMatch, foreground, mix(background, yellow, search_match_blend))
  set(theme.editor.searchActive, background, accent)
  set(theme.editor.bracketMatch, nil, selection)
  set(theme.diff.added, nil, mix(background, green, diff_blend))
  set(theme.diff.deleted, nil, mix(background, red, diff_blend))
  set(theme.diff.modified, nil, mix(background, yellow, diff_blend))
  set(theme.diff.gutterAdded, green)
  set(theme.diff.gutterDeleted, red)
  set(theme.diff.gutterModified, yellow)
  set(theme.diff.gutterBookmark, accent)
  set(theme.scrollbar, muted, surface)

  local roles = {
    comment = muted,
    string = green,
    keyword = magenta,
    number = yellow,
    operator = foreground,
    ["function"] = accent,
    type = cyan,
    builtin = cyan,
    variable = blue,
    punctuation = foreground,
    tag = red,
    attribute = yellow,
    regexp = bright_red,
    heading = bright_magenta,
    quote = at(8, muted),
    inserted = bright_green,
    deleted = bright_red,
    invalid = bright_red,
    control = bright_magenta,
    storage = bright_yellow,
    constant = bright_blue,
    escape = bright_cyan,
    parameter = bright_white,
    property = bright_cyan,
    self = bright_magenta,
    namespace = cyan,
    decorator = bright_red,
    link = bright_blue,
    code = bright_green,
    interpolation = bright_cyan,
    selector = bright_yellow,
    readonlyVariable = bright_magenta,
  }
  for role, value in pairs(roles) do
    theme.syntax[role].fg = safe(value, background, foreground)
  end
  theme.syntax.comment.italic = true
  theme.syntax.heading.bold = true
  theme.syntax.quote.italic = true
  theme.syntax.invalid.bold = true

  theme.terminal.foreground = foreground
  theme.terminal.background = background
  theme.terminal.selection = selection
  local terminal_names = {
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
    "brightBlack", "brightRed", "brightGreen", "brightYellow", "brightBlue",
    "brightMagenta", "brightCyan", "brightWhite",
  }
  for index, name in ipairs(terminal_names) do
    if ansi[index - 1] then theme.terminal[name] = ansi[index - 1] end
  end
  theme.tokenColors = token_colors(token_document, background, foreground)
  drop_empty_groups(theme)
  return theme
end

local ttt = require("ttt")
local fs = require("ttt.fs")
local settings = require("ttt.settings")
local json = require("ttt.json")

local palette_path = "~/.local/state/omarchy/current/theme/colors.toml"
local token_path = "~/.local/state/omarchy/current/theme/vscode-theme.json"
local output_path = "{config}/themes/omarchy.json"
local poll_interval_ms = 2000

local last_input_key
local last_output
local last_error
local reload_pending = false

local function report(message)
  if message == last_error then return end
  ttt.log("warn", "Omarchy theme: " .. message)
  -- Status-bar notification so a setup problem is visible without opening the
  -- output panel. Older hosts without ttt.notify still get the log line.
  if ttt.notify then ttt.notify("Omarchy theme: " .. message, "warn") end
  last_error = message
end

local function input_part(value)
  value = value or ""
  return tostring(#value) .. ":" .. value
end

local function reload_active_theme()
  if not reload_pending then return end
  if settings.get("theme") ~= "omarchy" then
    reload_pending = false
    return
  end
  if ttt.exec_command("settings.reload") then
    reload_pending = false
    last_error = nil
  else
    report("snapshot updated, but settings.reload command was unavailable")
  end
end

local function poll()
  local palette, palette_error = fs.read(palette_path)
  if not palette then
    report("palette unavailable: " .. tostring(palette_error))
    return
  end

  local token_source, token_error = fs.read(token_path)
  local input_key = input_part(palette)
    .. input_part(token_source and "present" or "unavailable")
    .. input_part(token_source or token_error or "")
  if input_key == last_input_key then
    reload_active_theme()
    return
  end

  local token_document
  if token_source then token_document = json.decode(token_source) end
  local theme, convert_error = M.convert(palette, token_document)
  if not theme then
    report(convert_error)
    return
  end

  local output, encode_error = json.encode(theme)
  if not output then
    report("could not encode generated theme: " .. tostring(encode_error))
    return
  end
  if output == last_output then
    last_input_key = input_key
    last_error = nil
    reload_active_theme()
    return
  end

  local written, write_error = fs.write(output_path, output)
  if not written then
    report("could not write {config}/themes/omarchy.json; create the themes directory (mkdir -p ~/.config/ttt/themes) or check its permissions: " .. tostring(write_error))
    return
  end

  last_input_key = input_key
  last_output = output
  last_error = nil
  reload_pending = true
  reload_active_theme()
end

ttt.register({})
ttt.set_timeout(100, poll)
ttt.set_interval(poll_interval_ms, poll)
