---
layout: post
title: "my local env setup"
date: 2025-12-03
categories: 
  - platform engineering
  - configuration management
  - devsecops
---
today, i would like delve into my local environment setup and my experiments/approaches/dabbling with the same in this write up

developer experiences are very close to my heart and when it comes to providing/using one locally, an opinionated setup is crucial that is extensible, fast and simple for me

as a `devsecops` engineer, my day to day tech stack involves the following:

- `docker`
- `kubernetes`
- `python`
- `ansible`
- `github-actions`
- `istio`
- `prometheus` & `grafana`
- `aws` - managed services
- `azure`  - managed services
- `wsl` - 🔥 (my home as a windows enterprise user) 

## my experience needs

i would like a local environment that:

1. can be setup fast, is reproducible and isolated
2. all my `variables` are version controlled including `secrets`
3. all my tooling is always there for me for any version that i need across different repos that i may use
4. i need not duplicate my vars or tooling across projects
5. i have flexibility to run specific tasks for housekeeping or workflows around my project
6. i have the flexiblity to switch between `dev`, `pre` and `prod` in a very seamless manner which is extensible all the way till `CI/CD`

## where i started

my practices today have evolved over multiple years of playing with different tooling that support my needs

### runtime versioning

as part of this journey, i started off with [asdf](https://asdf-vm.com/) which worked for me amazingly well...for a while. `asdf` works by wrapping a [shim](https://asdf-vm.com/manage/versions.html#shims) that execs into the name and version of the tool that we specify in the file. 

a typical `.tool-versions` file looked as follows for me:

```text
python            3.11.10  # https://github.com/danhper/asdf-python.git
awscli            2.11.27  # https://github.com/MetricMike/asdf-awscli.git
helm              3.15.4   # https://github.com/Antiarchitect/asdf-helm.git
kubectl           1.29.11  # https://github.com/asdf-community/asdf-kubectl.git
github-cli        2.62.0   # https://github.com/bartlomiejdanek/asdf-github-cli.git
gomigrate         4.17.0   # https://github.com/joschi/asdf-gomigrate.git
golang            1.23.8   # https://github.com/asdf-community/asdf-golang.git
nodejs            18.19.1  # https://github.com/asdf-vm/asdf-nodejs.git
pandoc            3.1.11.1 # https://github.com/Fbrisset/asdf-pandoc.git
postgres          15.10    # https://github.com/smashedtoatoms/asdf-postgres.git
trivy             0.66.0   # https://github.com/zufardhiyaulhaq/asdf-trivy.git
terraform         1.3.10   # https://github.com/asdf-community/asdf-hashicorp.git
terraform-docs    0.17.0   # https://github.com/looztra/asdf-terraform-docs.git
```

this was a game changer for me and i could just switch between versions with ease all the time. even have multiple versions of the same tool installed at a time and switch as needed. it also supported package installations via `pip`,`npm`,`go` etc for the specific languages. even the container image used `asdf` to installs specific tools as it allowed us to control all the versions from a single config file and could be installed in [parallel](https://asdf-vm.com/manage/configuration.html#asdf-concurrency)

version switch was as simple as

```shell
asdf set python 3.12
```

some of the experience aspects that it solved for me were:

- ✅ fast & reproducible with `.tool-versions`
- ✅ all my tooling is always there for me for any version that i need across different repos

### context based env sourcing

i was able to solve for tooling needs with `asdf` but i also wanted my variables specific to project or global ones completely version controlled including my secrets. for this i upgraded myself to *context based env sourcing* with *[direnv](https://direnv.net/) -> unclutter your `.profile`*

`direnv` allowed me to source/reset env variables specific to the project or the context of where i am present via a simple [.envrc](https://direnv.net/#quick-demo) file. the variables are unset when you move out of the context/directory automatically. it also provided a lovely [stdlib](https://direnv.net/man/direnv-stdlib.1.html) for specific functions that can be used to update `PATH` or `source_up` to inherit variables from parent `.envrc` -> a lovely feature to allow `configuration heirarchies`

my `.envrc` looked as below:

```shell
export HTTPS_PROXY='<redacted>'
export HTTP_PROXY='<redacted>'
export no_proxy='localhost,127.0.0.0/8,10.0.0.0/8'
export http_proxy='<redacted>'
export https_proxy='<redacted>'
export no_proxy='localhost,127.0.0.0/8,10.0.0.0/8'
export REGISTRY_BASE_URL='<redacted>'
export REGISTRY_NAMESPACE='devops'
export AWS_ACCESS_KEY_ID='AIKMJPGCFLFSVUQABCD1234'
export AWS_ROLE_ARN='arn:aws:iam::73778901234:role/iam_devops_role'
export AWS_ROLE_SESSION_NAME='AWS-CLI-devops'
export AWS_DEFAULT_OUTPUT_FORMAT='json'
export AWS_DEFAULT_REGION='us-east-1'
export AWS_REGION='us-east-1'
export AWS_ROLE_DURATION_SECONDS='28800'
export ARM_CLIENT_ID='4d54r3r-7958-4bbd-qwer-a511075abcd-1234'
export ARM_SUBSCRIPTION_ID='777765-88b0-43f7-a8a5-abcdqwertgb'
export ARM_TENANT_ID='4445yuhb967-e344-4ed4-8496-abcdtyuikmnh'
export AZURE_DEFAULTS_LOCATION='eastus'
export SOPS_AGE_KEY_FILE=${HOME}/.age.key

# decrypts the values from encrypted file
source_env <(sops decrypt -i --input-type=dotenv --output-type=dotenv .envsecrets)
```

to allow the loading of secrets , i found a nice approach to decrypt and use the variables as part of the same context with [sops](https://getsops.io/) and a simple encryption tool - [age](https://github.com/FiloSottile/age). I stored the `age key` in my password manager(2-factor-auth enabled) of choice to recreate/restore as needed, creating a very flexible and extensible workflow for me. all my secrets were part of `.envsecrets` 

my `.envsecrets`(encrypted) looked as below

```shell
export AWS_SECRET_ACCESS_KEY=ENC[AES256_GCM,data:LJbRr0KvaDYDkOYzxExSg+HPjnmUZQiiaQnN3HSrhBs09BOkcxYmBA==,iv:CHy1d4GYpnzzD/Kzx5dnFUbtS4ntmso6YcvRGitPA/M=,tag:8baq9dYejZGOlUFxESf83A==,type:str]
export ARM_CLIENT_SECRET=ENC[AES256_GCM,data:4gIqK+faHgHXKTHTn/UbtfE0LOOnY7U87UF9nd6ytoYQgGFPqNcrxw==,iv:dHTnZhGb8Fd0zKo9MmP/vv4dOZpMTs9EY66I9W8y37g=,tag:+m/jhqXnIgR+12En3ryFwA==,type:str]
export AGE_SECRET_KEY=ENC[AES256_GCM,data:/YlIVax1vuBOJKS06Q36Ov5Pq5d691h4jgjmrnT9yv2uayfwtO5oFSnK5Phc/KdkQPhAugbcQtgx32VfrJidxBsLaGAcXhJywLE=,iv:C3Gtzx6VFR+rskQ664d/wsdaUgCJ+npRBprfPc0b52g=,tag:hSBnJS1C4J7K/xIGOACL6w==,type:str]
export REGISTRY_PUSH_USERNAME=ENC[AES256_GCM,data:tlq8TdDSitHPKyVzSh7uuAoDlN5gM5HA5KaRq2mH,iv:u9gVZvHT7BrmENHWkglKGP22NcxqwF2QmtxutPA57lQ=,tag:epsW/DDiGWBZod2maQ7n+A==,type:str]
export REGISTRY_PUSH_PASSWORD=ENC[AES256_GCM,data:sNknanPBSn197qfLaZocJhXfcx2vwPE11xJYmc2Gb28=,iv:LiOnKfunjNC+e4Rs/91u8r/fqYUK3ESdc3SKn9ABAnE=,tag:QUJBiF+zya5CPtpIk0W0pQ==,type:str]
export ARTIFACTORY_USERNAME=ENC[AES256_GCM,data:nlCDY6c4KZw=,iv:bXFngIs154sUmL2E3A0vZgWLPJafVcwHIiR8JckqwXk=,tag:Y6ivL1b5XhtqzIlg7JbIFA==,type:str]
export ARTIFACTORY_PASSWORD=ENC[AES256_GCM,data:Mpk5Rk0GZviaH//ltCy+dHirytxuR5Fi7NN6DXPMmPR8coBMbI20cHwdD0Z7coivM5QTluRLjQLbr90+SLZbOhvUogb2iCp1Xg==,iv:4lA/Ykw0H6xXZIvj4tOtl46cTCikynk2DaO77HOy2Lw=,tag:wR5Sm7bXDzuQJuTFZxENDA==,type:str]
...
# omitted for brevity
```

my `.envrc` sourcing the `.envsecrets.json` was as follows. this allowed me to check in my variables into `git` along with `secrets`(encrypted) allowing me to solve for

- ✅ all my `variables` are version controlled including `secrets`
- ✅ i need not duplicate my vars or tooling across projects
- ✅ i have the flexibility to switch between `dev`, `pre` and `prod` in a very seamless manner which is extensible all the way till `CI/CD`

my directory structure with `direnv` for different environments looked as below

```text
.
├── .envrc
├── .envrc.dev
├── .envrc.pre
├── .envrc.prod
├── .envsecrets.dev
├── .envsecrets.pre
└── .envsecrets.prod
```

and my main `.envrc` looked as below, allowing me to switch between specific env as needed

```shell
export ENV=${ENV:-dev}  # Default to dev; override via ENV=prod direnv reload
dotenv_if_exists ".envrc.$ENV"
```

with this it pretty much solved everything that i needed

### devcontainers

i also experimented with [devcontainers](https://containers.dev/) for my needs. it provided very clean separation and isolation for each project and everything was contextual inside the container specific to that project but it solved only one of things for me

- ✅ i have the flexibility to switch between `dev`, `pre` and `prod` in a very seamless manner which is extensible all the way till `CI/CD`


### my combined stack

`asdf` and `direnv` provided me with the complete stack i needed...pretty much, so my project level structure was as follows and with this, i could source the tooling and variables of choice with ease specific to the account am working with - `dev`, `pre` or `prod`

```text
.
├── .envrc
├── .envrc.dev
├── .envrc.pre
├── .envrc.prod
├── .envsecrets.dev
├── .envsecrets.pre
├── .envsecrets.prod
└── .tool-versions
```

it also allows me to enable further nesting into directories if needed and load my tools,env,secrets in a more contextual manner if needed

## where it failed

### asdf and direnv

although, it was pretty utilitarian with `asdf` and `direnv` , i missed the following aspects

- ✖️ *no `make` like experience* -> ability to run custom `tasks` around my project
- ✖️ *tool dependencies* -> cases where a certain tool like `sops` is needed before decryption can work due to cyclic dependency
- ✖️ *additional package needs* -> `asdf` python builds are from source, needing lot of additional dev packages on the system which needs separate cleanup, this inside a container also adds bloat
- ✖️ `direnv` needs explicit `source_up` directive to know what files to source from parent
- ✖️ *no binary installs via gh releases* -> doesn't support `github` releases binary URLs, needed in case plugin is not available

### devcontainers

devcontainers are indeed very promising in this regard allowing you to use the same container for `development` and `CI/CD` workflows, however
- ✖️ *bloated `CI/CD` image* -> devcontainer from devex standpoint needs lot of additional tools unlike `CI/CD` where this would make the image size large
- ✖️ *pull consumes time* -> pulls take considerable time especially when you are using devcontainer with lot of tools, like in my case
- ✖️ *rebuild hell* -> happens for small updates in the devcontainer `Dockerfile` or `devcontainer.json` , slowing the overall speed
- ✖️ *config hierarchies not supported* -> env variables for each project level devcontainer needs to be defined though they might be common
- ✖️ *needs regular pruning locally* -> at times i have run out of disk space in my laptop 


## where i am now

as i continued on this path for making my setup better, i was particularly intrigued by a few aspects that i already experienced

- *configuration heirarchy*
- *versioned env vars & secrets*
- *automatic decryption of secrets locally*
- *switch with ease, `dev`, `pre`, `prod`* 
- *reproducible, fast, simple*

and i needed

- *define/run custom tasks*

and i stumbled across [mise](https://mise.jdx.dev/), and voila!!! -> *Devtools, Environments & Tasks*. it was all of what `asdf`, `direnv` already gave me + `tasks` , and all of these packaged together with even better experience

as part of this setup, i have the following structure, the use is as simple as `export MISE_ENV=dev`

```text
.
├── .envsecrets.json # global secrets (encrypted)
├── mise.toml        # global vars, tools, tasks
└── project
    ├── .envsecrets.dev.json  # dev env specific secrets (encrypted)
    └── mise.dev.toml         # dev env specific vars, tools, tasks
```

when i entire my project directory with the `export MISE_ENV=dev` set, all my tools with specific versions are switched, vars are updated and specific project related tasks are available as well -> [configuration heirarchy](https://mise.jdx.dev/configuration.html#configuration-hierarchy)

my `mise.dev.toml` looks as below

```toml
# mise.dev.toml
[env]
PROJECT_ROOT = "{{env.PWD}}"
TF_LOG = "ERROR"
TF_LOG_PATH = "/tmp/terraform-run.log"
ANSIBLE_VAULT_PASSWORD_FILE = "{{env.PROJECT_ROOT}}/.vault-pass"
ANSIBLE_COLLECTIONS_PATH = "{{env.PROJECT_ROOT}}/.ansible/collections"
VIRTUAL_ENV = "{{env.PROJECT_ROOT}}/.venv"
UV_PROJECT_ENVIRONMENT = "{{env.PROJECT_ROOT}}/.venv"
_.python.venv = { path = "{{env.VIRTUAL_ENV}}", create = true, python = "3.11" }
_.file = { path = "{{env.PROJECT_ROOT}}/.envsecrets.json", redact = true }
_.path = { path = ["{{env.PROJECT_ROOT}}/.venv/bin"] }
_.source = { path = "{{env.PROJECT_ROOT}}/tools/utils.sh", tools = true }


[tools]
node = "20.19"
terraform = "1.3"
terraform-docs = "0.17"
gomigrate = "4.17"
trivy = "0.67"
pandoc = "3.1"
"github:jphastings/jwker" = "0.2.2"


[tasks.install-pip-modules]
description = "install python modules from tools/requirements.txt"
run = "uv pip install --no-cache-dir -r {{env.PROJECT_ROOT}}/tools/requirements.txt"


[tasks.install-node-modules]
description = "install node modules"
run = "npm install -g @angular/cli@17.1.2"


[tasks.install-ansible-collections]
description = "install ansible galaxy collections from tools/requirements.yaml"
run = [
  "ansible-galaxy collection install -r {{env.PROJECT_ROOT}}/tools/requirements.yaml",
  "uv pip install --no-cache-dir -r {{env.ANSIBLE_COLLECTIONS_PATH}}/ansible_collections/azure/azcollection/requirements.txt",
  "uv pip install --no-cache-dir msal==1.34.0 msal-extensions==1.3.1",
]


[tasks.install-addon-tools]
# ref: https://www.postgresql.org/download/linux/debian/
confirm = 'this would prompt for sudo password for installation, are you ready to proceed?'
description = "install addon tools - postgresql-client"
run = [
  # install packages
  "sudo apt-get update && sudo apt-get install ca-certificates curl -y",

  # setup postgres repo
  "sudo install -d /usr/share/postgresql-common/pgdg",
  "sudo -E curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc",
  """sudo bash -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'""",

  # install postgresql-cli
  "sudo apt-get update",
  "sudo apt-get install -y postgresql-client-15",
]


[tasks.generate-terraform-plugin-cache-config]
description = "setup local terraform plugin cache config"
run = '''
mkdir -p {{ env.HOME }}/.terraform.d/plugin-cache
cat << EOF > {{ env.HOME }}/.terraformrc
plugin_cache_dir   = "{{ env.HOME }}/.terraform.d/plugin-cache"
disable_checkpoint = true
EOF
'''


[tasks.setup]
description = "setup local environment"
run = [
  { tasks = [
    "install-pip-modules",
    "install-node-modules",
    "install-addon-tools",
    "generate-terraform-plugin-cache-config",
  ] }, # runs in parallel
  { task = "install-ansible-collections" },
]


[settings]
jobs = 5
python.uv_venv_auto = true
aqua.github_attestations = false
not_found_auto_install = false
```


and my global `mise.toml` & `.envsecrets.json` is as below:

> NOTE: some values are `<redacted>` due to sensitive nature of enterprise env

```toml
[env]
HTTPS_PROXY = '<redacted>'
HTTP_PROXY = '<redacted>'
no_proxy = 'localhost,127.0.0.0/8,10.0.0.0/8'
http_proxy = '<redacted>'
https_proxy = '<redacted>'
no_proxy = 'localhost,127.0.0.0/8,10.0.0.0/8'
REGISTRY_BASE_URL = '<redacted>'
REGISTRY_NAMESPACE = 'devops'
AWS_ACCESS_KEY_ID = 'AIKMJPGCFLFSVUQABCD1234'
AWS_ROLE_ARN = 'arn:aws:iam::771978901234:role/iam_devops_role'
AWS_ROLE_SESSION_NAME = 'AWS-CLI-devops'
AWS_DEFAULT_OUTPUT_FORMAT = 'json'
AWS_DEFAULT_REGION = 'us-east-1'
AWS_REGION = 'us-east-1'
AWS_ROLE_DURATION_SECONDS = '28800'
ARM_CLIENT_ID = '5454665tf-7958-4bbd-qwer-a511075abcd-1234'
ARM_SUBSCRIPTION_ID = '77773434-88b0-43f7-a8a5-abcdqwertgb'
ARM_TENANT_ID = '44446yhu-e344-4ed4-8496-abcdtyuikmnh'
AZURE_DEFAULTS_LOCATION = 'eastus'
_.file = { path = "{{env.HOME}}/.envsecrets.json", redact = true }


[tools]
usage = 'latest'
python = "3.11"
helm = "4.0"
kubectl = "1.33"
kustomize = "5.6"
flux2 = "2.7"
uv = "0.9"
yq = "4.45"
jq = "1.8"
age = "1.2.1"
sops = "3.11"
aws = "2.11.27"
pipx = "1.8"


[tasks.install-apt-packages]
confirm = 'this would prompt for sudo password for installation, are you ready to proceed?'
description = 'setup local environment'
run = [
  'sudo apt-get update',
  'sudo apt-get install -y fastfetch bsdextrautils fastfetch bpytop tree fzf procs du-dust bat starship lsd kubectx',
]


[tasks.install-docker-engine]
# ref: https://docs.docker.com/engine/install/debian/
# note: the install will prompt for sudo password
confirm = 'this would prompt for sudo password for installation, are you ready to proceed?'
description = 'install docker-engine'
run = '''
sudo apt-get update && sudo apt-get install ca-certificates curl -y
sudo apt-get remove $(dpkg --get-selections docker.io docker-compose docker-doc podman-docker containerd runc | cut -f1)
sudo install -m 0755 -d /etc/apt/keyrings
sudo -E curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo bash -c 'cat <<EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF'
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl restart docker
sudo usermod -aG docker {{ env.USER }}
'''


[tasks.setup-docker-config]
confirm = 'this would prompt for sudo password for installation, are you ready to proceed?'
description = 'setup ~/.docker/config.json & /etc/docker/daemon.json with proxy settings and auth'
run = '''
DOCKER_AUTH=$(echo -n "{{ env.REGISTRY_AMBER_DEVOPS_PUSH_USERNAME }}:{{ env.REGISTRY_AMBER_DEVOPS_PUSH_PASSWORD }}" | base64 -w0)
mkdir -p {{ env.HOME }}/.docker
cat << EOF > {{ env.HOME }}/.docker/config.json
{
  "auths": {
    "{{ env.REGISTRY_BASE_URL }}/{{ env.REGISTRY_NAMESPACE }}": {
      "auth": "$DOCKER_AUTH"
    }
  },
  "proxies": {
    "default": {
      "httpProxy": "{{ env.http_proxy }}",
      "httpsProxy": "{{ env.https_proxy }}",
      "noProxy": "{{ env.no_proxy }}"
    }
  }
}
EOF
unset DOCKER_AUTH

sudo /bin/bash -c "cat << EOF > /etc/docker/daemon.json
{
  \"proxies\": {
    \"http-proxy\": \"{{ env.http_proxy }}\",
    \"https-proxy\": \"{{ env.https_proxy }}\",
    \"no-proxy\": \"{{ env.no_proxy }}\"
  }
}
EOF"
sudo systemctl restart docker
'''


[tasks.setup-git-config]
description = 'setup ~/.gitconfig file'
run = '''
cat << EOF > {{ env.HOME }}/.gitconfig
[http]
  proxy = {{ env.http_proxy }}
[https]
  proxy = {{ env.https_proxy }}
[user]
  email = raghavender.nagarajan@intel.com
  name = Raghavender Nagarajan
[core]
  autocrlf = false
  eol = lf
  editor = vim
[pull]
  rebase = true
EOF
'''


[tasks.setup-ssh-config]
description = 'setup ~/.ssh/config'
run = '''
mkdir -p {{ env.HOME }}/.ssh
cat << EOF > {{ env.HOME }}/.ssh/config
Host github.com
     Hostname github.com
     ProxyCommand nc -X connect -x {{ env.http_proxy | trim | replace(from="http://", to="") }} %h %p
EOF
'''


[tasks.setup-aliases]
description = 'setup ~/.aliases.sh'
run = '''
cat << EOF > {{ env.HOME }}/.aliases.sh
alias k='kubectl'
alias kx='kubectx'
alias ks='kubens'
alias cat='batcat'
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias ll='ls -la'
alias lt='ls --tree'
alias top='bpytop'
alias du='dust'
alias bathelp='bat --plain --language=help'
help() {
    "$@" --help 2>&1 | bathelp
}
alias ps=procs
EOF
'''


[tasks.setup-bash-completions]
description = 'setup ~/.bash_completions.sh'
run = '''
cat << EOF > {{ env.HOME }}/.bash_completions.sh
source <(kubectl completion bash)
source <(helm completion bash)
source <(kustomize completion bash)
source <(trivy completion bash)
source <(flux completion bash)
source <(docker completion bash)
eval "\$(uv generate-shell-completion bash)"
complete -o default -F __start_kubectl k
complete -C "$(which aws_completer)" aws
complete -C terraform terraform
EOF
'''


[tasks.setup-functions]
description = 'setup ~/.functions.sh'
run = '''
cat << EOF > {{ env.HOME }}/.functions.sh
# 1. apt-search
apts() {
  selected=\$(apt-cache search '' | batcat --paging=never | \
  fzf --ansi --preview="apt show {1}" --preview-window=up:5:wrap --delimiter=' ' --nth=1)

  if [ -n "\$selected" ]; then
    pkg=\$(echo "\$selected" | awk '{print $1}')
    echo "Installing package: \$pkg"
    sudo apt-get install -y "\$pkg"
  else
    echo "No package selected."
  fi
}
EOF
'''


[tasks.setup-profile]
description = 'setup ~/.profile'
run = '''
grep -q 'eval "$(fzf --bash)"' {{ env.HOME }}/.profile || echo 'eval "$(fzf --bash)"' >> {{ env.HOME }}/.profile
grep -q 'eval "$(starship init bash)"' {{ env.HOME }}/.profile || echo 'eval "$(starship init bash)"' >> {{ env.HOME }}/.profile
grep -q 'eval "$($HOME/.local/bin/mise activate bash)"' {{ env.HOME }}/.profile || echo 'eval "$($HOME/.local/bin/mise activate bash)"' >> {{ env.HOME }}/.profile
grep -q 'export PATH="$HOME/.local/bin/:$PATH"' {{ env.HOME }}/.profile || echo 'export PATH="$HOME/.local/bin/:$PATH"' >> {{ env.HOME }}/.profile
grep -q 'source {{ env.HOME }}/.aliases.sh' {{ env.HOME }}/.profile || echo 'source {{ env.HOME }}/.aliases.sh' >> {{ env.HOME }}/.profile
grep -q 'source {{ env.HOME }}/.bash_completions.sh' {{ env.HOME }}/.profile || echo 'source {{ env.HOME }}/.bash_completions.sh' >> {{ env.HOME }}/.profile
grep -q 'source {{ env.HOME }}/.functions.sh' {{ env.HOME }}/.profile || echo 'source {{ env.HOME }}/.functions.sh' >> {{ env.HOME }}/.profile
'''


[tasks.print-message]
description = 'print notes'
run = ['echo "✅ all setup completed successfully - restart your shell to load"']


[tasks.setup]
description = 'setup local environment'
run = [
  { task = 'install-apt-packages' },
  { task = 'install-docker-engine' },
  { tasks = [
    'setup-docker-config',
    'setup-git-config',
    'setup-ssh-config',
    'setup-aliases',
    'setup-bash-completions',
    'setup-functions',
    'setup-profile',
  ] },
  { task = 'print-message' },
]


[settings]
jobs = 4
aqua.github_attestations = false
auto_install = false
trusted_config_paths = ['~/projects/']
```

```text
// .envsecrets.json
{
  "AWS_SECRET_ACCESS_KEY": "ENC[AES256_GCM,data:LJbRr0KvaDYDkOYzxExSg+HPjnmUZQiiaQnN3HSrhBs09BOkcxYmBA==,iv:CHy1d4GYpnzzD/Kzx5dnFUbtS4ntmso6YcvRGitPA/M=,tag:8baq9dYejZGOlUFxESf83A==,type:str]",
  "ARM_CLIENT_SECRET": "ENC[AES256_GCM,data:4gIqK+faHgHXKTHTn/UbtfE0LOOnY7U87UF9nd6ytoYQgGFPqNcrxw==,iv:dHTnZhGb8Fd0zKo9MmP/vv4dOZpMTs9EY66I9W8y37g=,tag:+m/jhqXnIgR+12En3ryFwA==,type:str]",
  "AGE_SECRET_KEY": "ENC[AES256_GCM,data:/YlIVax1vuBOJKS06Q36Ov5Pq5d691h4jgjmrnT9yv2uayfwtO5oFSnK5Phc/KdkQPhAugbcQtgx32VfrJidxBsLaGAcXhJywLE=,iv:C3Gtzx6VFR+rskQ664d/wsdaUgCJ+npRBprfPc0b52g=,tag:hSBnJS1C4J7K/xIGOACL6w==,type:str]",
  "REGISTRY_PUSH_USERNAME": "ENC[AES256_GCM,data:tlq8TdDSitHPKyVzSh7uuAoDlN5gM5HA5KaRq2mH,iv:u9gVZvHT7BrmENHWkglKGP22NcxqwF2QmtxutPA57lQ=,tag:epsW/DDiGWBZod2maQ7n+A==,type:str]",
  "REGISTRY_PUSH_PASSWORD": "ENC[AES256_GCM,data:sNknanPBSn197qfLaZocJhXfcx2vwPE11xJYmc2Gb28=,iv:LiOnKfunjNC+e4Rs/91u8r/fqYUK3ESdc3SKn9ABAnE=,tag:QUJBiF+zya5CPtpIk0W0pQ==,type:str]",
  "ARTIFACTORY_USERNAME": "ENC[AES256_GCM,data:nlCDY6c4KZw=,iv:bXFngIs154sUmL2E3A0vZgWLPJafVcwHIiR8JckqwXk=,tag:Y6ivL1b5XhtqzIlg7JbIFA==,type:str]",
  "ARTIFACTORY_PASSWORD": "ENC[AES256_GCM,data:Mpk5Rk0GZviaH//ltCy+dHirytxuR5Fi7NN6DXPMmPR8coBMbI20cHwdD0Z7coivM5QTluRLjQLbr90+SLZbOhvUogb2iCp1Xg==,iv:4lA/Ykw0H6xXZIvj4tOtl46cTCikynk2DaO77HOy2Lw=,tag:wR5Sm7bXDzuQJuTFZxENDA==,type:str]",
  "sops": {
    "age": [
      {
        "recipient": "age19mtwumj6gt9qa6du3pvf336qn6za974wz5crtvz9jm3xm6mjcq8sabcd",
        "enc": "-----BEGIN AGE ENCRYPTED FILE-----\nYWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSB6RC9OZnp4VVNzSG9ScXc5\nVHNJcHQ0UzJmbDlLYjFXbS9BU2h1RXVXVEVFCmxMT043QVkxcWJjSzBNNXBXV2ky\ndlRJcDlRYmJHV1R1cTdBemlwVWJGNmMKLS0tIEswMkk4UEs2WnlHY2NGWXNmd3Y4\nN1FCaVpXb1VOMmdta3FEWkxDTUFDU0kKyqJ/cwxETgZkUax7LJ3gSM91dc8b+kB4\nvLQQVnB3iDUauAOzj/Ij16wF0A2VPBDIRzqhuMB1/fm8TYXy03zbZg==\n-----END AGE ENCRYPTED FILE-----\n"
      }
    ],
    "lastmodified": "2025-12-02T10:09:26Z",
    "mac": "ENC[AES256_GCM,data:A29MjHuUdrYYRpcjNIA5Z0iSRh/ooAYoUdz3LmRpnEewnVgDI2MwmKAQV+4gd+VTTXL6rEexQm9oM/f5ChSzc/b+St9Ty7OU1petpfs+1vPokFcCFe9x+2q4M2weiI8nDseWCRE3KUbGNsNzbJVM/yGXyxH2H46yZPtRpsXA+kM=,iv:FjKDFbtwUiRZz70fMWwYDn5d6L0PrdwP8DeSYNMjkIc=,tag:lmXhqKDyA5MYVK8/suibEg==,type:str]",
    "unencrypted_suffix": "_unencrypted",
    "version": "3.11.0"
  }
}
```

all my tools, env, tasks are inherited via configuration hierarchies for ease of use w.r.t switching between versions & overriding variables in a seamless way and one config file provides me with all the capabilities i need

my `mise ls` gives me the below inside my `project` -> *inheriting/overriding via configuration hierarchies*

```text
❯ mise ls
Tool                     Version  Source                               Requested
age                      1.2.1    ~/mise.toml                          1.2.1
aws                      2.11.27  ~/mise.toml                          2.11.27
flux2                    2.7.5    ~/mise.toml                          2.7
github:jphastings/jwker  0.2.2    ~/projects/saas-infra/mise.dev.toml  0.2.2
gomigrate                4.17.1   ~/projects/saas-infra/mise.dev.toml  4.17
helm                     4.0.1    ~/mise.toml                          4.0
jq                       1.8.1    ~/mise.toml                          1.8
kubectl                  1.33.6   ~/mise.toml                          1.33
kustomize                5.6.0    ~/mise.toml                          5.6
node                     20.19.6  ~/projects/saas-infra/mise.dev.toml  20.19
pandoc                   3.1      ~/projects/saas-infra/mise.dev.toml  3.1
pipx                     1.8.0    ~/mise.toml                          1.8
python                   3.11.14  ~/mise.toml                          3.11
sops                     3.11.0   ~/mise.toml                          3.11
terraform                1.3.10   ~/projects/saas-infra/mise.dev.toml  1.3
terraform-docs           0.17.0   ~/projects/saas-infra/mise.dev.toml  0.17
trivy                    0.67.2   ~/projects/saas-infra/mise.dev.toml  0.67
usage                    2.8.0    ~/mise.toml                          latest
uv                       0.9.13   ~/mise.toml                          0.9
yq                       4.45.4   ~/mise.toml                          4.45
```

what a lovely approach for managing configuration at scale 💖


## is this my golden setup?

for now, yes. i first got a grasp of configuration hierarchies through the `ansible` inventory patterns that can be used for large infrastructure repo and `direnv` gave me that experience for local environment, however with `mise` it has raised the bar considerably for me packaging all the goodness across the tools i experienced in a single place

with this i can now, have a local env that:

- ✅ can be setup fast, is reproducible and isolated
- ✅ all my `variables` are version controlled including `secrets`
- ✅ all my tooling is always there for me for any version that i need across different repos that i may use
- ✅ i need not duplicate my vars or tooling across projects -> just inherit/override as needed
- ✅ i have flexibility to run specific tasks for housekeeping or workflows around my project
- ✅ i have the flexibility to switch between `dev`, `pre` and `prod` in a very seamless manner

other value adds that i see are:

- ✅ mise tasks can be a nice addon to gh-actions tasks to avoid complex logic inside gh-actions
- ✅ considerable amount of disk space is saved locally

can this be extended to `CI/CD`? absolutely yes! and it considerably simplifies the `Dockerfile` as well allowing consistent experience and code similar to how you setup your local env

overall, i am all in with [mise](https://mise.jdx.dev/) for my day to day use 

i am thankful to the great work done by [jdx](https://github.com/jdx) with [mise](https://mise.jdx.dev/)

✌️

