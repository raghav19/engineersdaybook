# The sandbox side of a build. The command `sandbox-build` runs the recipe below.
# Run it in the folder to build: `sandbox-build app:dev` or `sandbox-build app:dev path/to/folder path/in/folder/Containerfile`.
# The recipe packs the folder, pushes it to the registry and sends a spec to the host listener over the socket.
# The listener builds the image on the host. Its log comes back over the socket, line by line.
# The recipe ends with the exit code of the build.

set quiet

registry := env('SANDBOX_BUILD_REGISTRY', 'ghcr.io/raghav19/engineersdaybook')
socket   := env('SANDBOX_BUILD_SOCKET', '/run/sandbox/proxy/build.sock')
# The proxy replaces this placeholder with the real token. The sandbox never holds the token.
token    := env('GHCR_PUSH_TOKEN', 'sandbox-placeholder-GHCR_PUSH_TOKEN')

# A build can wait behind the builds of other agents. Run it in the background if it can take longer than the tool timeout.
[no-cd]
[script('bash')]
build $image $folder='.' $file='Containerfile':
    set -euo pipefail
    registry='{{ registry }}'
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    # 1. Pack the folder as a tar. Leave out .git. The host accepts at most 64 MB.
    tar -C "$folder" --exclude=./.git -cf "$work/context.tar" .
    [ "$(stat -c %s "$work/context.tar")" -le 67108864 ] || { echo 'sandbox-build: the folder is larger than 64 MB' >&2; exit 1; }

    # 2. Push the tar to the registry as an image with one layer, and read its digest.
    # The login goes to a private folder, so the sandbox keeps no login file.
    # crane writes progress lines and a warning about the login file. run shows them only if crane fails.
    run() { "$@" 2>"$work/err" || { cat "$work/err" >&2; exit 1; }; }
    export DOCKER_CONFIG="$work/docker"
    printf %s '{{ token }}' | run crane auth login "${registry%%/*}" -u "$(cut -d/ -f2 <<<"$registry")" --password-stdin >/dev/null
    tag="$registry/build-context:$(date +%s)-$RANDOM"
    run crane append -f "$work/context.tar" -t "$tag" >/dev/null
    digest="$(run crane digest "$tag")"
    context="$registry/build-context@$digest"

    # 3. Send the spec to the host and print the log as it arrives.
    # socat stops 0.5 s after it sends the spec, unless -t is higher. The listener closes the connection when the build ends.
    spec="$(jq -cn --arg image "$image" --arg file "$file" --arg context "$context" '{image: $image, file: $file, context: $context}')"
    printf '%s\n' "$spec" | socat -t 86400 - UNIX-CONNECT:'{{ socket }}' | tee "$work/log" \
        || { echo "sandbox-build: no listener on {{ socket }}. Run on the host: just sandbox build-listen" >&2; exit 1; }

    # 4. The listener writes the last line itself, after the build ends.
    last="$(tail -n 1 "$work/log")"
    case "$last" in
        'sandbox-build: exit '*) exit "${last#sandbox-build: exit }" ;;
    esac
    echo 'sandbox-build: the connection ended before the build finished' >&2
    exit 1
