# env-config-management

sample configs of my local env management with `configuration heirarchy` pattern. more about this can be read in my blog -> [how i manage config sprawl effectively](https://raghav19.github.io/engineersdaybook/how-i-manage-config-sprawl-effectively)

## setup

### install
- install [mise](https://mise.jdx.dev/getting-started.html)
- fork/clone my repo and navigate to `./code/env-config-management`

### in action: config hierarchy level 0 -> global
- install tools and setup env
```shell
# install tools
mise install

# verify tools
mise ls

# verify env vars
mise env

# also can be seen using
env
```

### in action: config hierarchy level 1 -> project-x

- now navigate to `./code/env-config-management/my-project`

- install tools and setup env -> config hierarchy level 1
```shell
export MISE_ENV=dev

# install tools 
# NOTE: inherits from mise.toml & mise.dev.toml
mise install

# verify tools
mise ls

# verify env 
# NOTE: inherits vars from mise.toml & mise.dev.toml)
mise env

# also can be seen using
env
```

### managing secrets
- generate new `agekey`
```shell
age-keygen -o $HOME/.config/mise/age.txt
# Public key: <public key> -> NOTE THIS
```

- create your own `.envsecrets.json` & encrypt it using public key from previous step
```shell
sops encrypt -i --age "<public key>" .envsecrets.json
```

- similar way for your `DEV` specific secrets it can be defined inside the project under `.envsecrets.dev.json` and encrypted and version controlled in similar fashion

- the secret is referenced as part of `mise.toml` and `mise.dev.toml` as below which would be decrypted by `mise` and loaded
```shell
# mise.toml
_.file = { path = "{{env.HOME}}/.envsecrets.json", redact = true }

# mise.dev.toml
_.file = { path = "{{ env.PROJECT_ROOT }}/.envsecrets.dev.json", redact = true }
```

- as a robust backup solution, you should backup your `$HOME/.config/mise/age.txt` to a password manager or vault for future use 

### managing custom workflows
- housekeeping and custom workflows can be done using mise tasks which are also part of the `.mise.toml` and `.mise.dev.toml` file

- list available tasks using
```shell
mise tasks ls
```

- run tasks
```shell
mise run <task-name>
```

- more on this [here](https://mise.jdx.dev/tasks/) 

## other references
- [supported ecosystems/package-managers](https://mise.jdx.dev/dev-tools/backends/)
- [configuration heirarchy](https://mise.jdx.dev/configuration.html#configuration-hierarchy)
- [secrets management](https://mise.jdx.dev/environments/secrets/)

✌️