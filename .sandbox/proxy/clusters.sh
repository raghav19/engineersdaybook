#!/bin/bash
# The cluster gateway of the sandbox. `just sandbox clusters` runs it. It has two modes:
#   clusters.sh              read your kubeconfig and ../clusters.yaml, then write the files that the sandbox and the proxy need
#   clusters.sh token NAME   make a token for the cluster NAME and write it to the token file of the proxy
# It reads only public fields of your kubeconfig: the server, the CA and the type of login. It writes no credential.
# Only the mode `token` writes one, into a file with the mode 0600 on the host.
#
# Files that it writes (the folder is ~/.local/state/sandbox):
#   kube/kubeconfig                  the kubeconfig of the sandbox, with placeholders and no CA
#   upstream-ca.pem                  the system CAs plus the CA of each cluster. The proxy reads it as SSL_CERT_FILE.
#   tokens/NAME                      the token of a cluster. The proxy reads it and swaps it in for the placeholder.
#   ~/.config/sandbox/iron-proxy.yaml   the base ./iron-proxy.yaml plus a rule and a secret for each cluster
# The variables CLUSTERS_POLICY, SANDBOX_STATE and SANDBOX_PROXY_CONFIG change the paths. The tests use them.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
policy=${CLUSTERS_POLICY:-$here/../clusters.yaml}
state=${SANDBOX_STATE:-$HOME/.local/state/sandbox}
config=${SANDBOX_PROXY_CONFIG:-$HOME/.config/sandbox/iron-proxy.yaml}
system_ca=/etc/ssl/certs/ca-certificates.crt
name_re='^k8s_[a-z0-9_]+$'
for tool in jq yq; do command -v "$tool" >/dev/null || { echo "clusters: $tool not found. Install it, for example with mise install." >&2; exit 1; }; done

# The type of login of a user in your kubeconfig. Only the names of the fields are read, never their values.
login_of() {
  jq -r --arg u "$2" '.users[] | select(.name == $u) | .user
    | if has("exec") then "exec-plugin" elif has("client-certificate-data") or has("client-certificate") then "client-cert" elif has("token") then "token" else "other" end' <<<"$1"
}

# The access profile of a context: the first rule that matches its name.
access_of() {
  local pattern profile
  while IFS=$'\t' read -r pattern profile; do
    # shellcheck disable=SC2053
    [[ $1 == $pattern ]] && { echo "$profile"; return 0; }
  done < <(yq -r '.policy[] | [.match, .access] | @tsv' "$policy")
  return 0
}

if [[ ${1:-} == token ]]; then
  name=${2:?usage: clusters.sh token NAME}
  [[ $name =~ $name_re ]] || { echo "clusters: a name looks like k8s_dev" >&2; exit 1; }
  cfg=$(kubectl config view --raw -o json)
  user=$(jq -r --arg n "$name" '.contexts[] | select(.name == $n) | .context.user' <<<"$cfg")
  [[ -n $user ]] || { echo "clusters: your kubeconfig has no context $name" >&2; exit 1; }
  login=$(login_of "$cfg" "$user")
  [[ $login == client-cert ]] || { echo "clusters: the login type $login is not supported yet for $name" >&2; exit 1; }
  umask 077
  mkdir -p "$state/tokens"
  if kubectl --context "$name" create token "$(yq -r '.token.serviceaccount' "$policy")" -n "$(yq -r '.token.namespace' "$policy")" \
      --duration="$(yq -r '.token.duration' "$policy")" > "$state/tokens/$name.new"; then
    mv -f "$state/tokens/$name.new" "$state/tokens/$name"
    echo "clusters: token for $name written to $state/tokens/$name"
  else
    rm -f "$state/tokens/$name.new"
    echo "clusters: kubectl could not make a token for $name. Does the ServiceAccount exist?" >&2
    exit 1
  fi
  exit 0
fi

host=$(hostname)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
: > "$work/clusters"; : > "$work/users"; : > "$work/contexts"; : > "$work/rules"; : > "$work/secrets"; : > "$work/cas"
cfg=''
if command -v kubectl >/dev/null; then cfg=$(kubectl config view --raw -o json 2>/dev/null || true); else echo "clusters: kubectl not found, so no cluster is exposed" >&2; fi
[[ -n $cfg ]] || cfg='{}'

while IFS=$'\t' read -r name cluster user; do
  [[ -n $name ]] || continue
  access=$(access_of "$name")
  if [[ -z $access || $access == none ]]; then continue; fi
  if ! [[ $name =~ $name_re ]]; then echo "clusters: skip $name (a name looks like k8s_dev)" >&2; continue; fi
  server=$(jq -r --arg c "$cluster" '.clusters[] | select(.name == $c) | .cluster.server' <<<"$cfg")
  # The proxy refuses a loopback address, and a client sends no server name for an IP. So use the name of this host.
  server=$(sed -E "s#//(127\.0\.0\.1|localhost)([:/]|\$)#//$host\2#" <<<"$server")
  # DNS names ignore case. A client may send the name in lower case, and the proxy compares the text, so write it in lower case.
  server=$(sed -E 's#(https?://)([^:/]+)#\1\L\2#' <<<"$server")
  apihost=$(sed -E 's#https?://([^:/]+).*#\1#' <<<"$server")
  login=$(login_of "$cfg" "$user")
  methods=$(yq -o=json ".access[\"$access\"].methods" "$policy" | jq -r 'join(", ")')
  [[ -n $methods && $methods != null ]] || { echo "clusters: skip $name (no access profile $access)" >&2; continue; }
  ca=$(jq -r --arg c "$cluster" '.clusters[] | select(.name == $c) | .cluster["certificate-authority-data"] // empty' <<<"$cfg" | base64 -d 2>/dev/null || true)
  if [[ -z $ca ]]; then
    ca_file=$(jq -r --arg c "$cluster" '.clusters[] | select(.name == $c) | .cluster["certificate-authority"] // empty' <<<"$cfg")
    [[ -n $ca_file && -r $ca_file ]] && ca=$(cat "$ca_file")
  fi
  [[ -n $ca ]] && printf '%s\n' "$ca" >> "$work/cas"
  placeholder="sandbox-placeholder-$(tr 'a-z' 'A-Z' <<<"$name")"
  echo "clusters: expose $name -> $server (access $access, login $login)" >&2
  printf -- '- {name: %s, cluster: {server: "%s"}}\n' "$name" "$server" >> "$work/clusters"
  printf -- '- {name: %s, user: {token: %s}}\n' "$name" "$placeholder" >> "$work/users"
  printf -- '- {name: %s, context: {cluster: %s, user: %s}}\n' "$name" "$name" "$name" >> "$work/contexts"
  printf -- '- {host: %s, methods: [%s]}\n' "$apihost" "$methods" >> "$work/rules"
  # The path is relative. The unit runs the proxy in ~/.local/state/sandbox.
  printf -- '- source: {type: file, path: tokens/%s, ttl: 5m}\n  replace: {proxy_value: %s, match_headers: [Authorization]}\n  rules: [{host: %s}]\n' "$name" "$placeholder" "$apihost" >> "$work/secrets"
done < <(jq -r '.contexts[]? | [.name, .context.cluster, .context.user] | @tsv' <<<"$cfg")

umask 077
mkdir -p "$state/kube" "$state/tokens" "$(dirname "$config")"
chmod 755 "$state/kube"

if [[ -s $work/contexts ]]; then
  { echo "apiVersion: v1"; echo "kind: Config"; echo "clusters:"; cat "$work/clusters"; echo "users:"; cat "$work/users"
    echo "contexts:"; cat "$work/contexts"; echo "current-context: $(head -1 "$work/contexts" | sed -E 's/^- \{name: ([^,]+),.*/\1/')"; } > "$work/kubeconfig"
else
  printf 'apiVersion: v1\nkind: Config\nclusters: []\nusers: []\ncontexts: []\n' > "$work/kubeconfig"
fi
chmod 644 "$work/kubeconfig"
mv -f "$work/kubeconfig" "$state/kube/kubeconfig"

cat "$system_ca" "$work/cas" > "$work/upstream-ca.pem"
mv -f "$work/upstream-ca.pem" "$state/upstream-ca.pem"

# The proxy config: the base plus a rule and a secret for each cluster. Write a new file and move it, so that a link to the base stays a link.
if [[ -s $work/contexts ]]; then
  RULES=$work/rules SECRETS=$work/secrets yq '
    (.transforms[] | select(.name == "allowlist") | .config.rules) += load(strenv(RULES)) |
    (.transforms[] | select(.name == "secrets") | .config.secrets) += load(strenv(SECRETS))' "$here/iron-proxy.yaml" > "$work/iron-proxy.yaml"
else
  cp "$here/iron-proxy.yaml" "$work/iron-proxy.yaml"
fi
chmod 644 "$work/iron-proxy.yaml"
mv -f "$work/iron-proxy.yaml" "$config"
echo "clusters: wrote $state/kube/kubeconfig, $state/upstream-ca.pem and $config" >&2
