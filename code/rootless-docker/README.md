# sandboxing with rootless docker

when you harden a container you probably reach for the same things I do. run as non-root, drop all capabilities, no-new-privileges, maybe a seccomp profile

changing what the docker daemon itself runs as is usually the last thing on that list & often it’s not on it

i went looking for cases where that decision actually mattered — three real container escapes

→ [CVE-2019–5736](https://www.cve.org/CVERecord?id=CVE-2019-5736) — blocked. the maintainer noted default apparmor and selinux policy did not stop it, user namespaces did.

→ [CVE-2025–52881](https://www.cve.org/CVERecord?id=CVE-2025-52881) — blocked. the runc advisory says LSM profiles “likely do not provide much protection,” and that rootless containers “entirely mitigated” the escalation.

→ [CVE-2024–21626](https://www.cve.org/CVERecord?id=CVE-2024-21626) — downgraded, not prevented. the escape still lands. it just lands as your user

the rule underneath all three — rootless blocks an escape when the final step needs a write to something only host root owns

read more about this [here](https://medium.com/@sairam19/rootless-docker-the-hardening-step-you-reach-for-last-and-cves-that-argue-you-shouldnt-1d3e6fa7e63a?sharedUserId=sairam19)

## getting started

my setup is `omarchy` - arch based

### pre-reqs 
```shell
uname -r # kernel > 5.11
cat /proc/sys/kernel/unprivileged_userns_clone # must be 1
grep "^$(whoami):" /etc/subuid /etc/subgid # must have entry for subuid/subgid >= 65536
stat -fc %T /sys/fs/cgroup/ # must be cgroup2fs
```

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
echo 'export DOCKER_HOST=unix://$XDG_2RUNTIME_DIR/docker.sock' >> ~/.bashrc
```

### verify
```shell
docker info
# context: should read rootless
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

#### check-2 - the containers real host UUID
```shell
PID=$(docker inspect -f '{{.State.Pid}}' probe)
ps -o pid,user,cmd -p "$PID"
grep -E '^(Uid|Gid):' /proc/$PID/status
```

### check-3 - from inside the container, see the "fake root"

```shell
docker exec probe id                # uid=0(root) — looks real
docker exec probe cat /proc/self/uid_map   # the mapping table that says otherwise
```


## bind-mount failure & fix

- check the mount failure
```shell
mkdir -p ~/rootless-lab && cd ~/rootless-lab

docker run --rm -v "$PWD":/data -u 1000:1000 alpine sh -c 'echo hi > /data/from-container.txt'

ls -ln from-container.txt   # owner column: 100999, not 1000
 ss -ltn | grep ':80\b'
```

- fixing using linux ACL
```shell
# giving permission to
# user->100999->read,write,X means execute only if this is a directory
# the permission is given for current & future(note the d) inheritance rules
setfacl -Rm d:u:100999:rwX,u:100999:rwX ./data

# full guide here -> https://wiki.archlinux.org/title/Access_Control_Lists
```

## exposing priviledged ports

anything < 1024 would be a priviledged port and to test this

```shell
docker run -d --name porttest -p 80:80 nginx
docker ps --format '{{.Status}} | {{.Ports}}'
ss -ltnp | grep ':80\b' # nothing on the host
curl --max-time 5 http://localhost:80/ # nothing -> FAILED
```

### how to resolve this

- **Solution 1:** Publish container on high port (`-p 8080:80`)

- **Solution 2:** Enable host-wide access to 80 for any unpriviledged process
```shell
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-rootless-port80.conf

sudo sysctl --system #restart


# 3. Confirm the setting, then retry
sysctl net.ipv4.ip_unprivileged_port_start   # expect: = 80

docker run --rm -d -p 80:80 --name port-test nginx

curl -s -o /dev/null -w '%{http_code}\n' http://localhost:80   # expect: 200


docker stop port-test
```