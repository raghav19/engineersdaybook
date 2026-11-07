# sandboxing with rootless docker

when you harden a container you probably reach for the same things I do. run as non-root, drop all capabilities, no-new-privileges, maybe a seccomp profile

changing what the docker daemon itself runs as is usually the last thing on that list & often it’s not on it

i went looking for cases where that decision actually mattered — three real container escapes

→ [CVE-2019-5736](https://www.cve.org/CVERecord?id=CVE-2019-5736) — rootless blocks the final write. the maintainer noted that the default apparmor policy did not stop it. the default selinux policy did not stop it on fedora. user namespaces, where host root is not mapped, did.

→ [CVE-2025-52881](https://www.cve.org/CVERecord?id=CVE-2025-52881) — rootless blocks the final write. the runc advisory says LSM profiles “likely do not provide much protection,” and that rootless containers “entirely mitigated” the escalation.

→ [CVE-2024-21626](https://www.cve.org/CVERecord?id=CVE-2024-21626) — downgraded, not prevented. the escape still lands. it just lands as your user. the maintainers wrote that user namespaces “do not stop it from happening entirely.”

the rule underneath all three — rootless does not fix the runc bug. it blocks the final step when that step needs a write to something only host root owns

read more about this [here](https://medium.com/@sairam19/rootless-docker-the-hardening-step-you-reach-for-last-and-cves-that-argue-you-shouldnt-1d3e6fa7e63a?sharedUserId=sairam19)

## getting started

my setup is `omarchy` - arch based

### pre-reqs 
```shell
uname -r # kernel 5.11 or later (needed for the overlay2 storage driver)
cat /proc/sys/kernel/unprivileged_userns_clone # must be 1
grep "^$(whoami):" /etc/subuid /etc/subgid # must have entry for subuid/subgid >= 65536
command -v newuidmap newgidmap # both must print a path
stat -fc %T /sys/fs/cgroup/ # cgroup2fs is needed only for resource limits (--cpus, --memory, --pids-limit)
```

### install the packages
```shell
# docker and rootlesskit are in the arch extra repository
sudo pacman -S --needed docker rootlesskit

# docker-rootless-extras is in the AUR
# it has dockerd-rootless.sh and the user units docker.service and docker.socket
yay -S docker-rootless-extras
```

for other distributions, follow the [docker rootless guide](https://docs.docker.com/engine/security/rootless/)

### disable root docker daemon
```shell
# assumes you already have an installation with default docker
sudo systemctl disable --now docker.service docker.socket
sudo rm -f /var/run/docker.sock
```

### enable lingering
```shell
sudo loginctl enable-linger "$(whoami)"
loginctl show-user "$(whoami)" -p Linger    # confirm: Linger=yes

# by default systemd kills every --user service the moment the last login session ends
```

### enable rootless docker
```shell
systemctl --user enable --now docker.socket
```

### point CLI to rootless docker socket
```shell
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
echo 'export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock' >> ~/.bashrc
```

### verify
```shell
docker info
# Server section: "Security Options" must list "rootless"
```



## verifying the setup

### proving a container is actually rootless

```shell
# start a target container
docker run -d --name probe alpine sleep 3600
```

#### check-1 - the daemon level facts

```shell
docker info --format '{{json .SecurityOptions}}' # expect entry "name=rootless"
```

#### check-2 - the containers real host UID
```shell
PID=$(docker inspect -f '{{.State.Pid}}' probe)
ps -o pid,user,cmd -p "$PID"
grep -E '^(Uid|Gid):' /proc/$PID/status
```

#### check-3 - from inside the container, see the "fake root"

```shell
docker exec probe id                # uid=0(root) — looks real
docker exec probe cat /proc/self/uid_map   # the mapping table that says otherwise
```


## bind-mount failure & fix

- check the mount failure
```shell
mkdir -p ~/rootless-lab && cd ~/rootless-lab

docker run --rm -v "$PWD":/data -u 1000:1000 alpine sh -c 'echo hi > /data/from-container.txt'

# expect: Permission denied
# container uid 1000 is host uid 100999
# your directory belongs to your user, so 100999 is "other" and cannot write

ls -ln from-container.txt   # expect: No such file or directory
```

100999 is the subuid start (100000) plus 999. your start value can differ, so read it in `/etc/subuid`

- fixing using linux ACL
```shell
# run this in ~/rootless-lab
# giving permission to
# user->100999->read,write,X means execute only if this is a directory
# the permission is given for current & future(note the d) inheritance rules
setfacl -Rm d:u:100999:rwX,u:100999:rwX .

# full guide here -> https://wiki.archlinux.org/title/Access_Control_Lists
```

- run the `docker run` command again. the file is now created
```shell
ls -ln from-container.txt   # owner column: 100999, not 1000
```

## exposing privileged ports

anything < 1024 would be a privileged port and to test this

```shell
# start from the default setting: this must print 1024, and nothing else may use port 80 on the host
sysctl net.ipv4.ip_unprivileged_port_start

docker run -d --name porttest -p 80:80 nginx
docker ps --format '{{.Status}} | {{.Ports}}'
ss -ltnp | grep ':80\b' # nothing on the host
curl --max-time 5 http://localhost:80/ # nothing -> FAILED

# cleanup
docker rm -f porttest
```

### how to resolve this

- **Solution 1:** Publish container on high port (`-p 8080:80`)

- **Solution 2:** Let any unprivileged process of any local user bind ports 80 to 1023. This is a host-wide change
```shell
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-rootless-port80.conf
sudo sysctl --system # reload the settings

# verify
sysctl net.ipv4.ip_unprivileged_port_start   # expect: = 80

# test with nginx container
docker run --rm -d -p 80:80 --name port-test nginx
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:80   # expect: 200

# cleanup
docker stop port-test
docker rm -f probe
```
