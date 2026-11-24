# The report of `mise run otel:report`. Input: the files of otelcol.
# Usage: jq -n -r -f otel-report.jq <files>

# --- Read the events ---
# OTLP JSON writes an integer as a string. num makes it a number.
def num: tonumber? // 0;
# A record has its attributes as a list. attrs makes one object of them.
def attrs: (.attributes // []) | map({(.key): (.value | .stringValue // .intValue // .doubleValue)}) | add // {};
def event($name): select((.["event.name"] // "" | ltrimstr("claude_code.")) == $name);

# --- Format ---
def left($n): tostring | .[:$n] | . + " " * ($n - length);
def right($n): tostring | " " * ($n - length) + .;
def human: if . >= 1e6 then "\(. / 1e5 | round / 10)M" elif . >= 1e3 then "\(. / 100 | round / 10)k" else "\(round)" end;
def usd: (. * 100 | round) as $c | "$\($c / 100 | floor).\("0\($c % 100)" | .[-2:])";
def percent($part; $whole): if $whole > 0 then $part / $whole * 100 else 0 end;
def pct: (. * 10 | round) as $x | "\($x / 10 | floor).\($x % 10)%";
def bar: (. / 5 | round) as $n | "█" * $n + "░" * (20 - $n);

# --- Print a table ---
# A row has a label, two texts (a and b) and a share from 0 to 100. The width is 78.
def row: "  " + (.label | left(26)) + (.a | right(10)) + (.b | right(10)) + (.share | pct | right(8)) + "  " + (.share | bar);
def table($title; $a_name; $b_name; $rows):
  "", "  \($title)",
  ("  " + ("" | left(26)) + ($a_name | right(10)) + ($b_name | right(10)) + ("SHARE" | right(8))),
  ($rows[] | row);
# Group the requests, sum the cost of each group and sort the groups by cost.
def cost_rows(f; $total):
  group_by(f) | map({label: (.[0] | f), n: length, cost: (map(.cost) | add)}) | sort_by(-.cost)
  | map({label, a: (.n | tostring), b: (.cost | usd), share: percent(.cost; $total)});

# --- Collect the data ---
[inputs | .resourceLogs[]?.scopeLogs[]?.logRecords[]? | attrs + {time: (.timeUnixNano | num / 1e9)}] as $events
| [$events[] | event("api_request") | {
    session: (.["session.id"] // "?"), time, model: (.model // "?"), source: (.query_source // "?"),
    cost: (.cost_usd | num), input: (.input_tokens | num), output: (.output_tokens | num),
    cache_read: (.cache_read_tokens | num), cache_write: (.cache_creation_tokens | num),
    feature: (if .["skill.name"] then "skill:" + .["skill.name"]
              elif .["plugin.name"] then "plugin:" + .["plugin.name"]
              elif .["mcp_server.name"] then "mcp:" + .["mcp_server.name"]
              else "(none)" end)
  }] as $requests
| [$events[] | event("tool_result") | {tool: (.tool_name // "?"), bytes: (.tool_result_size_bytes | num)}] as $tools

# --- Print the report ---
| if ($requests | length) == 0 then
    "No api_request events yet. Run Claude Code in the sandbox, then run this report again."
  else
    ($requests | length) as $count
    | ($requests | map(.cost) | add) as $cost
    | ($requests | map(.time)) as $times
    | ($requests | [
        {label: "cacheRead", sum: (map(.cache_read) | add)},
        {label: "cacheCreation", sum: (map(.cache_write) | add)},
        {label: "output", sum: (map(.output) | add)},
        {label: "input", sum: (map(.input) | add)}
      ] | sort_by(-.sum)) as $tokens
    | ($tokens | map(.sum) | add) as $token_sum
    | ($requests | group_by(.session) | map({
        label: "\(.[0].session[:8])  \(map(.time) | min | strflocaltime("%m-%d %H:%M"))",
        peak: (map(.input + .cache_read + .cache_write) | max),
        cost: (map(.cost) | add)
      }) | sort_by(-.cost) | .[:5]) as $sessions
    | ($tools | map(.bytes) | add // 0) as $tool_sum
    | ($tools | group_by(.tool) | map({label: .[0].tool, n: length, bytes: (map(.bytes) | add)}) | sort_by(-.bytes) | .[:8]) as $tool_groups
    | "Claude Code usage · \($times | min | strflocaltime("%Y-%m-%d %H:%M")) → \($times | max | strflocaltime("%Y-%m-%d %H:%M"))",
      "\($requests | group_by(.session) | length) sessions · \($count) requests · \($cost | usd)",
      table("TOKENS BY TYPE"; "AVG/REQ"; "TOKENS";
            $tokens | map({label, a: (.sum / $count | round | human), b: (.sum | human), share: percent(.sum; $token_sum)})),
      table("COST BY MODEL"; "REQUESTS"; "COST"; $requests | cost_rows(.model; $cost)),
      table("COST BY SOURCE"; "REQUESTS"; "COST"; $requests | cost_rows(.source; $cost)),
      table("COST BY SKILL · PLUGIN · MCP"; "REQUESTS"; "COST"; $requests | cost_rows(.feature; $cost)),
      table("TOP SESSIONS BY COST"; "PEAK CTX"; "COST";
            $sessions | map({label, a: (.peak | human), b: (.cost | usd), share: percent(.cost; $cost)})),
      (if ($tools | length) > 0 then
         table("TOOL OUTPUT BY TOOL"; "CALLS"; "BYTES";
               $tool_groups | map({label, a: (.n | tostring), b: (.bytes | human), share: percent(.bytes; $tool_sum)}))
       else empty end)
  end
