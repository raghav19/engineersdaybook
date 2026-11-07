#!/usr/bin/env bash
# End-to-end test of the msbvm plugin and the delegate with a real SPIRE agent.
# It starts a throwaway SPIRE server and a throwaway SPIRE agent on this host.
# It never touches the cluster. It only reads the running VM and msb.db.
# Read tests/README.md before you change this script.
set -euo pipefail

VM=sandbox-dev
SPIRE_VERSION=1.15.5
TRUST_DOMAIN=mcp.local
SERVER_PORT=18081
AGENT_ID="spiffe://$TRUST_DOMAIN/test/agent"
DELEGATE_ID="spiffe://$TRUST_DOMAIN/node/sandbox-dev/user/raghav19/delegate"
VM_ID="spiffe://$TRUST_DOMAIN/node/sandbox-dev/user/raghav19/vm/$VM"
OTHER_VM_ID="spiffe://$TRUST_DOMAIN/node/sandbox-dev/user/raghav19/vm/other-vm"
MSB_DB="$HOME/.microsandbox/db/msb.db"

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(dirname "$TESTS_DIR")
CACHE_DIR="$HOME/.cache/agent-workload-identity/spire-$SPIRE_VERSION"
RELEASE="spire-$SPIRE_VERSION-linux-amd64-musl"

# Unix socket paths can have 108 characters at most, so the folder name is short.
BASE=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/awi-e2e.XXXXXX")
SERVER_PID=""
AGENT_PID=""
FAKE_PID=""
SLEEP_PID=""
FAILED=0

# Kill only the processes that this script started. Use the saved pids.
cleanup() {
  local pid
  for pid in "$AGENT_PID" "$FAKE_PID" "$SLEEP_PID" "$SERVER_PID"; do
    if [ -n "$pid" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$BASE"
}
trap cleanup EXIT INT TERM

info() { echo "== $*"; }
pass() { echo "PASS $1: $2"; }
fail() { echo "FAIL $1: $2"; FAILED=1; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Print the end of a log file without the join token.
show_log() {
  echo "--- $1 (last 25 lines) ---" >&2
  tail -n 25 "$1" 2>/dev/null | sed "s/$(cat "$BASE/token" 2>/dev/null || echo NOTOKEN)/<REDACTED>/g" >&2 || true
}

# Wait until a command succeeds. Arguments: seconds, then the command.
wait_for() {
  local seconds=$1 i
  shift
  for ((i = 0; i < seconds * 5; i++)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 0.2
  done
  return 1
}

# Print the pid of the real VMM of the VM, or nothing.
real_vmm_pid() {
  ps -eo pid=,args= >"$BASE/ps.txt"
  awk -v vm="$VM" '$2 ~ /(^|\/)msb$/ && $3 == "machine" {
    for (i = 4; i < NF; i++) if ($i == "--name" && $(i + 1) == vm) { print $1; exit }
  }' "$BASE/ps.txt"
}

# ---------- 1. SPIRE binaries (cached, checked with sha256sum) ----------
ensure_spire() {
  local archive="$CACHE_DIR/download/$RELEASE.tar.gz"
  local sums="$CACHE_DIR/download/${RELEASE}_sha256sum.txt"
  mkdir -p "$CACHE_DIR/download"
  if [ ! -f "$archive" ] || [ ! -f "$sums" ]; then
    info "download SPIRE $SPIRE_VERSION"
    gh release download "v$SPIRE_VERSION" -R spiffe/spire --clobber -D "$CACHE_DIR/download" \
      -p "$RELEASE.tar.gz" -p "${RELEASE}_sha256sum.txt"
  fi
  (cd "$CACHE_DIR/download" && sha256sum -c --quiet "${RELEASE}_sha256sum.txt") ||
    die "the checksum of the SPIRE archive is wrong. Remove $CACHE_DIR and run again."
  if [ ! -x "$CACHE_DIR/release/bin/spire-server" ] || [ ! -x "$CACHE_DIR/release/bin/spire-agent" ]; then
    info "unpack SPIRE $SPIRE_VERSION"
    rm -rf "$CACHE_DIR/release"
    mkdir "$CACHE_DIR/release"
    tar -xzf "$archive" -C "$CACHE_DIR/release" --strip-components=1
  fi
  SPIRE_SERVER="$CACHE_DIR/release/bin/spire-server"
  SPIRE_AGENT="$CACHE_DIR/release/bin/spire-agent"
}

# ---------- 2. Build the plugin, the delegate and the fake msb ----------
build_all() {
  mkdir -p "$BASE/bin" "$BASE/other" "$BASE/fake"
  info "build the plugin, the delegate, the e2e test binary and the fake msb"
  (cd "$PROJECT_DIR/plugin" && go build -o "$BASE/bin/msbvm" .)
  (cd "$PROJECT_DIR/delegate" && go build -o "$BASE/bin/delegate" .)
  (cd "$PROJECT_DIR/delegate" && go test -c -tags e2e -o "$BASE/bin/e2e.test" .)
  # The fake msb is built outside any Go module. The name of the file is "msb".
  (cd "$BASE" && go build -o "$BASE/fake/msb" "$TESTS_DIR/fakemsb/main.go")
  PLUGIN="$BASE/bin/msbvm"
  DELEGATE="$BASE/bin/delegate"
  E2E_TEST="$BASE/bin/e2e.test"
  PLUGIN_SHA=$(sha256sum "$PLUGIN" | cut -d' ' -f1)
}

# ---------- 3. Throwaway server ----------
start_server() {
  mkdir -p "$BASE/srv"
  SERVER_SOCK="$BASE/srv/server.sock"
  cat >"$BASE/server.conf" <<EOF
server {
  bind_address = "127.0.0.1"
  bind_port    = "$SERVER_PORT"
  socket_path  = "$SERVER_SOCK"
  trust_domain = "$TRUST_DOMAIN"
  data_dir     = "$BASE/srv"
  log_level    = "INFO"
}

plugins {
  DataStore    "sql"        { plugin_data { database_type = "sqlite3" connection_string = "$BASE/srv/ds.sqlite3" } }
  KeyManager   "memory"     { plugin_data {} }
  NodeAttestor "join_token" { plugin_data {} }
}
EOF
  info "start the throwaway server on 127.0.0.1:$SERVER_PORT"
  (cd "$BASE" && exec "$SPIRE_SERVER" run -config "$BASE/server.conf" >"$BASE/server.log" 2>&1) &
  SERVER_PID=$!
  wait_for 30 "$SPIRE_SERVER" healthcheck -socketPath "$SERVER_SOCK" || {
    show_log "$BASE/server.log"
    die "the server did not become healthy"
  }
}

# ---------- 4. Join token and entries ----------
register() {
  local uid
  uid=$(id -u)
  # The token goes to a file with mode 600. It is never printed.
  (umask 077 && "$SPIRE_SERVER" token generate -spiffeID "$AGENT_ID" -socketPath "$SERVER_SOCK" |
    sed -n 's/^Token: //p' >"$BASE/token")
  [ -s "$BASE/token" ] || die "no join token"

  info "create the entries (same IDs and selectors as the cluster, parent $AGENT_ID)"
  "$SPIRE_SERVER" entry create -socketPath "$SERVER_SOCK" -parentID "$AGENT_ID" -spiffeID "$DELEGATE_ID" \
    -selector "unix:uid:$uid" -selector "unix:path:$DELEGATE" >/dev/null
  "$SPIRE_SERVER" entry create -socketPath "$SERVER_SOCK" -parentID "$AGENT_ID" -spiffeID "$VM_ID" \
    -selector "msbvm:name:$VM" -selector "unix:uid:$uid" >/dev/null
  # The Go test binary needs the same rights as the delegate. It has another
  # path, so it gets one more entry with the ID of the delegate.
  "$SPIRE_SERVER" entry create -socketPath "$SERVER_SOCK" -parentID "$AGENT_ID" -spiffeID "$DELEGATE_ID" \
    -selector "unix:uid:$uid" -selector "unix:path:$E2E_TEST" >/dev/null
}

# ---------- 5. Throwaway agent ----------
start_agent() {
  # The admin socket is in another folder than the Workload API socket.
  mkdir -p "$BASE/agent" "$BASE/admin"
  chmod 700 "$BASE/agent" "$BASE/admin"
  ADMIN_SOCK="$BASE/admin/admin.sock"
  (umask 077 && cat >"$BASE/agent.conf" <<EOF
agent {
  data_dir             = "$BASE/agent"
  socket_path          = "$BASE/agent/agent.sock"
  admin_socket_path    = "$ADMIN_SOCK"
  authorized_delegates = ["$DELEGATE_ID"]
  trust_domain         = "$TRUST_DOMAIN"
  server_address       = "127.0.0.1"
  server_port          = "$SERVER_PORT"
  insecure_bootstrap   = true
  join_token           = "$(cat "$BASE/token")"
  log_level            = "INFO"
}

plugins {
  NodeAttestor     "join_token" { plugin_data {} }
  KeyManager       "memory"     { plugin_data {} }
  WorkloadAttestor "unix"       { plugin_data { discover_workload_path = true } }
  WorkloadAttestor "msbvm" {
    plugin_cmd      = "$PLUGIN"
    plugin_checksum = "$PLUGIN_SHA"
    plugin_data { db_path = "$MSB_DB" }
  }
}
EOF
  )
  info "start the throwaway agent"
  (cd "$BASE" && exec "$SPIRE_AGENT" run -config "$BASE/agent.conf" >"$BASE/agent.log" 2>&1) &
  AGENT_PID=$!
  wait_for 30 test -S "$ADMIN_SOCK" || {
    show_log "$BASE/agent.log"
    die "the admin socket did not appear"
  }
}

# Run the delegate binary $1 with the arguments that follow. Set OUT, ERR and RC.
run_delegate() {
  local bin=$1
  shift
  RC=0
  "$bin" "$@" >"$BASE/out.txt" 2>"$BASE/err.txt" || RC=$?
  OUT=$(cat "$BASE/out.txt")
  ERR=$(cat "$BASE/err.txt")
}

# The agent opens its sockets before it has the entries of its node. In this
# time it answers "no identity issued" to every caller. Call the delegate until
# the agent answers. E1 then runs the same call again and checks the result.
wait_for_entries() {
  local i
  for ((i = 0; i < 40; i++)); do
    run_delegate "$DELEGATE" -vm "$VM" -id "$VM_ID" -socket "$ADMIN_SOCK"
    if [ "$RC" -eq 0 ]; then
      info "the agent has its entries after $i retries"
      return 0
    fi
    sleep 0.5
  done
  return 0 # E1 reports the failure
}

# ---------- 6. Test cases ----------
has_key_text() { printf '%s\n%s\n' "$OUT" "$ERR" | grep -qi 'PRIVATE KEY'; }

test_e1() {
  local vmm_pid
  vmm_pid=$(real_vmm_pid)
  run_delegate "$DELEGATE" -vm "$VM" -id "$VM_ID" -socket "$ADMIN_SOCK"
  if [ "$RC" -ne 0 ]; then
    fail E1 "delegate exit code $RC: $ERR"
  elif ! grep -qx "spiffe_id=$VM_ID" <<<"$OUT"; then
    fail E1 "output has no spiffe_id=$VM_ID"
  elif has_key_text; then
    fail E1 "the output has private key text"
  else
    pass E1 "the delegate got $VM_ID for the real VMM pid $vmm_pid"
  fi
}

test_e2() {
  run_delegate "$DELEGATE" -vm "$VM" -id "$VM_ID" -socket "$ADMIN_SOCK"
  if [ "$RC" -eq 0 ] && grep -qx "spiffe_id=$VM_ID" <<<"$OUT"; then
    pass E2 "the second call returned the same SPIFFE ID"
  else
    fail E2 "second call: exit code $RC, error: $ERR"
  fi
}

# Send one pid with the Go test. The agent must return zero SVIDs.
run_pid_test() {
  local name=$1 pid=$2 what=$3
  if E2E_SOCKET="$ADMIN_SOCK" E2E_PID="$pid" "$E2E_TEST" -test.run TestPidIsRefused >"$BASE/gotest.txt" 2>&1; then
    pass "$name" "$what: the agent returned zero SVIDs"
  else
    fail "$name" "$what: $(grep -m1 'e2e_test.go' "$BASE/gotest.txt" || echo 'the test failed')"
  fi
}

test_e3() {
  sleep 600 &
  SLEEP_PID=$!
  run_pid_test E3 "$SLEEP_PID" "pid $SLEEP_PID is a plain sleep process"
}

test_e4() {
  "$BASE/fake/msb" machine --name "$VM" --sandbox-id 184 &
  FAKE_PID=$!
  # The exe name and the command line must look like the real VMM.
  if ! tr '\0' ' ' <"/proc/$FAKE_PID/cmdline" | grep -q -- "machine --name $VM --sandbox-id 184"; then
    fail E4 "the fake msb has the wrong command line"
    return
  fi
  run_pid_test E4 "$FAKE_PID" "pid $FAKE_PID is a fake msb with the command line of the VMM"
  # Stop the fake msb now. The delegate scans /proc by VM name. With two VMMs of
  # the VM, it would refuse to choose, and the next cases would fail.
  kill "$FAKE_PID" 2>/dev/null || true
  wait "$FAKE_PID" 2>/dev/null || true
  FAKE_PID=""
}

test_e5() {
  cp "$DELEGATE" "$BASE/other/delegate"
  run_delegate "$BASE/other/delegate" -vm "$VM" -id "$VM_ID" -socket "$ADMIN_SOCK"
  if [ "$RC" -ne 0 ] && grep -q 'code = PermissionDenied' <<<"$ERR"; then
    pass E5 "the agent denied the delegate at another path (exit code $RC)"
  else
    fail E5 "exit code $RC, error: $ERR $OUT"
  fi
}

test_e6() {
  # The socket does not exist. If the delegate called the agent, the error
  # would be about the socket. The error must be about the missing VMM.
  run_delegate "$DELEGATE" -vm no-such-vm -id "$VM_ID" -socket "$BASE/no-such.sock"
  if [ "$RC" -ne 0 ] && grep -q 'no VMM of the VM' <<<"$ERR" && ! grep -qi 'socket\|rpc error' <<<"$ERR"; then
    pass E6 "the delegate refused before a call to the agent (exit code $RC)"
  else
    fail E6 "exit code $RC, error: $ERR"
  fi
}

# The agent answers with the SVID of the VM. The delegate expects another ID.
# It must fail, and it must name both IDs. The agent does not know what the
# delegate meant, so only the delegate can make this check.
test_e7() {
  run_delegate "$DELEGATE" -vm "$VM" -id "$OTHER_VM_ID" -socket "$ADMIN_SOCK"
  if [ "$RC" -ne 0 ] && grep -q "expected ID $OTHER_VM_ID" <<<"$ERR" && grep -q "$VM_ID" <<<"$ERR" && ! grep -q '^spiffe_id=' <<<"$OUT"; then
    pass E7 "the delegate refused an SVID with another ID than it expected (exit code $RC)"
  else
    fail E7 "exit code $RC, error: $ERR $OUT"
  fi
}

main() {
  command -v go >/dev/null || die "go is not installed"
  command -v gh >/dev/null || die "gh is not installed"
  [ -n "$(real_vmm_pid)" ] || die "the VM $VM does not run. Start it and run this test again."
  ensure_spire
  build_all
  start_server
  register
  start_agent
  wait_for_entries
  test_e1
  test_e2
  test_e3
  test_e4
  test_e5
  test_e6
  test_e7
  if [ "$FAILED" -ne 0 ]; then
    show_log "$BASE/agent.log"
    echo "RESULT: FAIL"
    exit 1
  fi
  echo "RESULT: PASS"
}

main
