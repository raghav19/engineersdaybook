#!/bin/sh
# The tests of the rights in the build queue. `just sandbox queue-check` runs this file in a container with no network.
# Each line below is one test. "allowed" means the server runs the command. "blocked" means the server refuses it.
# The script prints ok or FAIL for each test and exits 1 if one test fails. The tests use the keys job:t1:* and remove them at the end.
[ -n "$QUEUE_WORKER_PASSWORD" ] || { echo 'FAIL  QUEUE_WORKER_PASSWORD is empty'; exit 1; }

# These four functions connect to the queue as one user. The agent has no password, so any password works.
cli()                   { valkey-cli -s /run/valkey/valkey.sock --no-auth-warning "$@" 2>&1; }
nobody()                { cli "$@"; }
agent()                 { cli --user agent --pass x "$@"; }
worker()                { cli --user worker --pass "$QUEUE_WORKER_PASSWORD" "$@"; }
worker_wrong_password() { cli --user worker --pass wrong "$@"; }

# These words in the answer mean that the server refused the command.
refused='NOPERM|NOAUTH|WRONGPASS|ERR'

failed=0
allowed() { if "$@" | grep -qE "$refused"; then echo "FAIL  allowed: $*"; failed=1; else echo "ok    allowed: $*"; fi; }
blocked() { if "$@" | grep -qE "$refused"; then echo "ok    blocked: $*"; else echo "FAIL  blocked: $*"; failed=1; fi; }

echo '--- no login'
blocked nobody PING
blocked worker_wrong_password PING

echo '--- the agent sends a job'
allowed agent SET job:t1:ctx abc
allowed agent SET job:t1:spec image=x
allowed agent LPUSH build:queue t1
allowed agent GET job:t1:status

echo '--- the agent can do nothing else'
blocked agent GET job:t1:ctx
blocked agent SET job:t1:status done
blocked agent LRANGE build:queue 0 -1
blocked agent KEYS '*'
blocked agent CONFIG GET dir
blocked agent EVAL 'return 1' 0
blocked agent FLUSHALL
blocked agent DEL job:t1:ctx

echo '--- the worker takes the job and writes the status'
allowed worker BLMOVE build:queue build:active RIGHT LEFT 1
allowed worker GET job:t1:ctx
allowed worker SET job:t1:status running
allowed agent GET job:t1:status

echo '--- the worker can do nothing else'
blocked worker FLUSHALL
blocked worker CONFIG GET dir

echo '--- remove the test keys'
worker LREM build:active 1 t1 > /dev/null
worker DEL job:t1:ctx job:t1:spec job:t1:status > /dev/null

exit $failed
