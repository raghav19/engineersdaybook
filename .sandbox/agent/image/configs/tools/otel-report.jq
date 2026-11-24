# The report of `mise run otel:report`. Input: the files of otelcol.
# Usage: jq -n -r -f otel-report.jq <files>
# Every section uses one grid. Widths: indent 2, label 22, A 11, B 14, share 8, gap 2, bar 20.

def rep($c; $n): if $n > 0 then $c * $n else "" end;
def lpad($n): tostring | . as $s | rep(" "; $n - ($s | length)) + $s;
def rpad($n): tostring | . as $s | $s + rep(" "; $n - ($s | length));
def cut($n): if length > $n then .[:$n - 1] + "…" else . end;
def commas: floor | tostring | . as $s | ($s | length) as $n | [range($n; 0; -3) as $i | $s[([$i - 3, 0] | max):$i]] | reverse | join(",");
def usd: (. * 100 | round) as $c | "$" + (($c / 100 | floor) | commas) + "." + (($c % 100) | tostring | if length < 2 then "0" + . else . end);
def pct: (. * 10 | round) as $x | "\($x / 10 | floor).\($x % 10)%";
def kb: if . < 10 then ((. * 10 | round) / 10 | tostring) else (round | commas) end;

# OTLP JSON: a number is a string in intValue.
def num: if type == "string" then (tonumber? // 0) elif type == "number" then . else 0 end;
def attrs: (.attributes // []) | map({key: .key, value: (.value | .stringValue // .intValue // .doubleValue // .boolValue)}) | from_entries;

def group_rows(keyf; af; bf; vf): group_by(keyf) | map({l: (.[0] | keyf), a: (map(af) | add), b: (map(bf) | add), v: (map(vf) | add)});
def top($n; $sum_a):
  sort_by(-.v)
  | if length > $n
    then .[:$n] + [.[$n:] as $r | {l: "(other)", a: (if $sum_a then ($r | map(.a) | add) else null end), b: ($r | map(.b) | add), v: ($r | map(.v) | add)}]
    else . end;

def hdr($ha; $hb): ("  " + ("" | rpad(22)) + ($ha | lpad(11)) + ($hb | lpad(14)) + ("SHARE" | lpad(8))) | sub("\\s+$"; "");
def row($tot; fa; fb):
  (if $tot > 0 then .v / $tot * 100 else 0 end) as $p
  | ($p / 100 * 20 | round) as $n
  | "  " + (.l | cut(22) | rpad(22)) + ((if .a == null then "" else (.a | fa) end) | lpad(11)) + (.b | fb | lpad(14)) + ($p | pct | lpad(8)) + "  " + rep("█"; $n) + rep("░"; 20 - $n);
def section($title; $ha; $hb; fa; fb):
  (map(.v) | add // 0) as $tot
  | "", ("  " + $title), hdr($ha; $hb), ("  " + rep("─"; 77)), (.[] | row($tot; fa; fb));
def box($l1; $l2):
  ("  ╭" + rep("─"; 75) + "╮"), ("  │ " + ($l1 | rpad(73)) + " │"), ("  │ " + ($l2 | rpad(73)) + " │"), ("  ╰" + rep("─"; 75) + "╯");

[ inputs
  | .resourceLogs[]?.scopeLogs[]?.logRecords[]?
  | attrs as $a
  | {n: (($a["event.name"] // .body.stringValue // "") | ltrimstr("claude_code.")), t: (.timeUnixNano | num / 1e9), a: $a} ] as $ev
| ($ev | map(select(.n == "api_request") | .a as $a | {
    s: ($a["session.id"] // "?"), t: .t, m: ($a.model // "?"), q: ($a.query_source // "?"),
    i: ($a.input_tokens | num), r: ($a.cache_read_tokens | num), w: ($a.cache_creation_tokens | num), o: ($a.output_tokens | num),
    c: ($a.cost_usd | num),
    k: (if $a["skill.name"] then "skill:" + $a["skill.name"] elif $a["plugin.name"] then "plugin:" + $a["plugin.name"] elif $a["mcp_server.name"] then "mcp:" + $a["mcp_server.name"] else "(none)" end)
  })) as $api
| ($ev | map(select(.n == "tool_result") | {n: (.a.tool_name // "?"), z: (.a.tool_result_size_bytes | num)})) as $tool
| if ($api | length) == 0 then
    "No api_request events yet. Run Claude Code in the sandbox, then run this report again."
  else
    ($api | length) as $n
    | ($api | map(.t) | min) as $t0
    | ($api | map(.t) | max) as $t1
    | ($t0 | strflocaltime("%Y-%m-%d %H:%M")) as $d0
    | ($t1 | strflocaltime("%Y-%m-%d %H:%M")) as $d1
    | ($api | group_by(.s) | length) as $ns
    | ($api | map(.c) | add) as $cost
    | box("Claude Code usage · \($d0) → \(if $d0[:10] == $d1[:10] then $d1[11:] else $d1 end)";
          "\($ns) sessions · \($n | commas) requests · \($cost | usd)"),
      ({cacheRead: ($api | map(.r) | add), cacheCreation: ($api | map(.w) | add), output: ($api | map(.o) | add), input: ($api | map(.i) | add)}
        | to_entries | map({l: .key, a: (.value / $n | round), b: .value, v: .value}) | top(10; true)
        | section("TOKENS BY TYPE"; "AVG/REQ"; "TOKENS"; commas; commas)),
      ($api | group_rows(.m; 1; .c; .c) | top(10; true) | section("COST BY MODEL"; "REQUESTS"; "COST"; commas; usd)),
      ($api | group_rows(.q; 1; .c; .c) | top(10; true) | section("COST BY SOURCE"; "REQUESTS"; "COST"; commas; usd)),
      ($api | group_rows(.k; 1; .c; .c) | top(10; true) | section("COST BY SKILL · PLUGIN · MCP"; "REQUESTS"; "COST"; commas; usd)),
      ($api | group_by(.s)
        | map({l: ((.[0].s | .[:8]) + "  " + (map(.t) | min | strflocaltime("%m-%d %H:%M"))), a: (map(.i + .r + .w) | max), b: (map(.c) | add), v: (map(.c) | add)})
        | top(10; false) | section("TOP SESSIONS BY COST"; "PEAK CTX"; "COST"; commas; usd)),
      (if ($tool | length) > 0
       then ($tool | group_rows(.n; 1; .z / 1024; .z) | top(10; true) | section("TOOL OUTPUT BY TOOL"; "CALLS"; "SIZE (KB)"; commas; kb))
       else empty end)
  end
