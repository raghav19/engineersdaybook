#!/usr/bin/env bash
# One-time root setup for the Docker + gVisor spike. Run it with: sudo bash <this file>
# It does five things. Read each step before you run it.
#   1. Check the SHA-512 of the gVisor tarball that was downloaded earlier.
#   2. Put runsc and its files in /usr/local/bin (owned by root, so no user can swap the binary).
#   3. Register three Docker runtimes (this edits /etc/docker/daemon.json and keeps your other keys):
#        runsc       no extra flags
#        runsc-uds   --host-uds=open                (lets the sandbox connect to a mounted host Unix socket)
#        runsc-suid  --host-uds=open --allow-suid   (for nested Podman with newuidmap)
#   4. Start the Docker daemon (it does not enable it at boot).
#   5. Give the user rana temporary read-write access to /var/run/docker.sock with an ACL.
#      Access to this socket is root-equivalent. The ACL ends when the daemon restarts.
#      Undo it earlier with: sudo setfacl -x u:rana /var/run/docker.sock
set -euo pipefail

SPIKES="<SPIKES>"
USER_NAME="rana"

# 1. checksum
( cd "${SPIKES}/G-dl" && sha512sum -c gvisor.tar.zstd.sha512 )

# 2. install into a root-owned folder
tar --zstd -xf "${SPIKES}/G-dl/gvisor.tar.zstd" -C /usr/local/bin
chown -R root:root /usr/local/bin/runsc /usr/local/bin/containerd-shim-runsc-v1 /usr/local/bin/gvisor-bin
/usr/local/bin/runsc --version

# 3. register the runtimes
cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak-before-gvisor"
/usr/local/bin/runsc install
/usr/local/bin/runsc install --runtime runsc-uds -- --host-uds=open
/usr/local/bin/runsc install --runtime runsc-suid -- --host-uds=open --allow-suid
echo "--- /etc/docker/daemon.json"
cat /etc/docker/daemon.json

# 4. start the daemon
systemctl start docker
sleep 2
systemctl is-active docker

# 5. temporary socket access for the spike user
setfacl -m "u:${USER_NAME}:rw" /var/run/docker.sock

docker info --format 'server={{.ServerVersion}} cgroup={{.CgroupDriver}}/{{.CgroupVersion}} runtimes={{range $k,$v := .Runtimes}}{{$k}} {{end}}'
echo "Done. A backup of the old config is /etc/docker/daemon.json.bak-before-gvisor"
