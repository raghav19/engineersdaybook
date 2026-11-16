#!/bin/sh
# The tests of the rights in the build queue. `just sandbox queue-check` runs this file in a gVisor container with no network.
# The container has only the socket folder, as the sandbox has. The worker password comes in the variable QUEUE_WORKER_PASSWORD.
# Each line is ok or FAIL. The script exits 1 if a line fails. The tests use the keys job:t1:*, and they remove them at the end.
[ -n "${QUEUE_WORKER_PASSWORD:-}" ] || { echo 'FAIL  the variable QUEUE_WORKER_PASSWORD is empty'; exit 1; }

sock=/run/valkey/valkey.sock
# a is the agent. w is the worker. The agent has no password, so any value logs it in.
a() { valkey-cli -s $sock --no-auth-warning --user agent --pass x "$@" 2>&1; }
w() { valkey-cli -s $sock --no-auth-warning --user worker --pass "$QUEUE_WORKER_PASSWORD" "$@" 2>&1; }

# expect NAME PATTERN OUTPUT: prints ok if OUTPUT matches PATTERN, and FAIL if it does not.
fail=0
expect() { if printf '%s' "$3" | grep -qE "$2"; then echo "ok    $1"; else echo "FAIL  $1 -> $3"; fail=1; fi; }

# No login.
expect 'no login: refused'                'NOAUTH'     "$(valkey-cli -s $sock ping 2>&1)"

# The agent sends a job and may do nothing else.
expect 'agent: SET context'               '^OK$'       "$(a SET job:t1:ctx abc EX 60)"
expect 'agent: SET spec'                  '^OK$'       "$(a SET job:t1:spec 'image=x tag=y')"
expect 'agent: LPUSH queue'               '^1$'        "$(a LPUSH build:queue t1)"
expect 'agent: read a missing status'     '^\[\]$'     "[$(a GET job:t1:status)]"
expect 'agent: GET context is blocked'    'NOPERM'     "$(a GET job:t1:ctx)"
expect 'agent: SET status is blocked'     'NOPERM'     "$(a SET job:t1:status done)"
expect 'agent: LRANGE queue is blocked'   'NOPERM'     "$(a LRANGE build:queue 0 -1)"
expect 'agent: KEYS is blocked'           'NOPERM'     "$(a KEYS '*')"
expect 'agent: CONFIG is blocked'         'NOPERM'     "$(a CONFIG GET dir)"
expect 'agent: EVAL is blocked'           'NOPERM'     "$(a EVAL 'return 1' 0)"
expect 'agent: FLUSHALL is blocked'       'NOPERM'     "$(a FLUSHALL)"
expect 'agent: DEL is blocked'            'NOPERM'     "$(a DEL job:t1:ctx)"

# The worker takes the job and writes the status. The agent reads the status.
expect 'worker: wrong password fails'     'WRONGPASS'  "$(valkey-cli -s $sock --no-auth-warning --user worker --pass wrong ping 2>&1)"
expect 'worker: BLMOVE takes the job'     '^t1$'       "$(w BLMOVE build:queue build:active RIGHT LEFT 1)"
expect 'worker: GET context'              '^abc$'      "$(w GET job:t1:ctx)"
expect 'worker: SET status'               '^OK$'       "$(w SET job:t1:status running)"
expect 'agent: reads the status'          '^running$'  "$(a GET job:t1:status)"
expect 'worker: FLUSHALL is blocked'      'NOPERM'     "$(w FLUSHALL)"
expect 'worker: CONFIG is blocked'        'NOPERM'     "$(w CONFIG GET dir)"

# Remove the test keys.
w LREM build:active 1 t1 >/dev/null
w DEL job:t1:ctx job:t1:spec job:t1:status >/dev/null
exit $fail
