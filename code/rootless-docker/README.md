# sandboxing with rootless docker

a setup to show how `rootless` docker helps in creating a fully secure sandbox for application execution

read more about this [here]

## getting started

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