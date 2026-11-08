#!/bin/sh
# Runs as root with CHOWN, SETUID, SETGID only. Gives the volume folders to agent, then drops to agent.
set -eu
for d in /home/agent/.claude /home/agent/.local/share/containers /home/agent/.cache/terraform-providers; do
  chown agent:agent "$d"
done
exec setpriv --reuid=agent --regid=agent --init-groups --inh-caps=-all "$@"
