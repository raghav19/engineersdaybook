# The attack cases of tests/attacks, run against the gateway. One line per OWASP id; the expected results are those of the profile of the
# cluster stack: phase-1 when its stack.yaml has the authn-jwt artifact, baseline when it has none.
set quiet

root := justfile_directory()
# Host side of the extraPortMappings in clusters/<cluster>/kind-config.yaml.
gateway_url := env('GATEWAY_URL', 'http://127.0.0.1:8080/mcp')

# run every tests/attacks case against the gateway of the cluster
[script('bash')]
run cluster='kind':
    set -eu
    name=$(yq .name {{ root }}/clusters/{{ cluster }}/kind-config.yaml)
    [ "$(kubectl config current-context)" = "kind-$name" ] \
      || { echo "kubectl context is not kind-$name; refusing to touch the wrong cluster" >&2; exit 1; }
    [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' {{ gateway_url }})" != 000 ] \
      || { echo "Nothing answers on {{ gateway_url }}. Run: just cluster up, and wait for Flux to apply the artifacts (the cluster needs the port mapping in clusters/{{ cluster }}/kind-config.yaml)" >&2; exit 1; }
    if yq -N '.metadata.name' {{ root }}/clusters/{{ cluster }}/sync/stack.yaml | grep -qx authn-jwt; then profile=phase-1; else profile=baseline; fi
    for t in {{ root }}/tests/attacks/MCP*/; do bash "$t/run.sh" "{{ gateway_url }}" "$profile"; done
