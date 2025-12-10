---
layout: post
title: "how we used configuration heirarchies to support a scale of 1million+ users per day in our saas-infra"
date: 2025-12-10
categories: 
  - platform-engineering
  - configuration-management
  - devsecops
  - ansible
  - aws
  - azure
---
ansible is a great configuration management tool and especially at scale it becomes imperative to use patterns and well tread paths to define/apply/operate on your infrastructure, but can it provide great orchestration capabilities as well?

in this write-up, i will go into the config pattern that scaled for us for our infra codebase that spans for supporting *<u>1 Million+ users per day, currently at 200K+ LOC</u>* all the way from dev to prod with our infrastructure tooling stack -> `terraform`, `ansible` and `python`

before i go any further, i would like to extend my sincere thanks to my colleagues and amazing engineers i have had the privilege to work with in this regard, [adam stenka](https://www.linkedin.com/in/adamstenka) and [wrobel wojciech](https://www.linkedin.com/in/wojciech-wrobel-3b8a30195) whose deep expertise and knowledge allowed us orchestrate this chaos together at scale

## where we started

`ansible` can be a great fit into orchestrating stacks of infrastructure related components which extends beyond standard provisioning with just `terraform`. `terraform` excels in provisioning but not in orchestrating stacks of components together. although there have been recent innovations in this regard with [terramate](https://terramate.io/rethinking-iac/how-to-structure-and-size-terraform-stacks/) and [terragrunt](https://terragrunt.gruntwork.io/docs/features/stacks/) , we chose `ansible` for operating the chaos at scale for us via specific patterns through the experience and expertise over the years

in our project which is multi-cloud involved a bunch of components ranging from AWS to Azure, a rough view of the architecture is as shown below:

![infra]({{ site.baseurl }}/images/infra.jpg)

our infrastructure and operations around DEV & TEST stacks involved a [dedicated gateway](https://istio.io/latest/docs/setup/additional-setup/gateway/#dedicated-application-gateway) model, allowing isolated application development and feature explorations per developer. orchestration of these components which involves some brownfield and mostly greenfield applications, we needed a declarative and at some places imperative model of operating infrastructure. 

to begin with `ansible` provided lovely orchestration capabilities out of the box with a native module for [community.general.terraform module – Manages a Terraform deployment (and plans) — Ansible Community Documentation](https://docs.ansible.com/projects/ansible/latest/collections/community/general/terraform_module.html) and we were able to fit this right into the multitude of infrastructure provisioning/configuration related roles we had and needed strong orchestration to do it in an [idempotent](https://en.wikipedia.org/wiki/Idempotence) fashion

although, this was great initially as we started with our infrastructure where our [inventory](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html) was minimal, however as we scaled and further added components and more deeper nuances within those components something started showing up for us very prominently -> `configuration sprawl` 

- duplication of configuration across components

  ```yaml
  # below both dev01 and dev02 have same pattern for cluster name but are duplicated at 2 places
  
  # inventories/DEV/group_vars/dev01.yaml
  eks:
    cluster_name: "{{ application | lower }}-eks-{{ aws_region }}-{{ env }}"
  
  # inventories/DEV/group_vars/dev02.yaml
  eks:
    cluster_name: "{{ application | lower }}-eks-{{ aws_region }}-{{ env }}"
  ```

- large yaml files to work with

  ```yaml
  # each component in the arch had parent keyword representing the 
  # inventories/DEV/group_vars/dev01.yaml
  eks:
   #...omitted for brevity
  
  apigw:
   #.. omitted for brevity
   
  # ... 15+ components
  ```

- nesting of configuration/component -> each of components listed had too much nesting underneath parent, causing a simple structural variable movement an extremely daunting task/effort

to solve this, we had to relook at the way we approach our configuration and how we defined our variables inside the ansible inventory pattern, we expanded to a more robust pattern that allows:

- `inheritance/overrides` over `duplication`
- `converged configuration` over `single large config file`
- `flattening of config variables` over `nested naming and definitions`

## how we solved it

the core of the problem was resolved through [configuration hierarchies](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html#how-variables-are-merged)

the inventory structure that scaled for us in this regard looked as below. each account, env and user space has its dedicated `group_vars` and `hosts` file telling the relationship between them

### inventory structure

```text
.
├── DEV
│   ├── dev02
│   │   ├── group_vars
│   │   │   ├── DEV -> ../../../group_vars/DEV/                              # symlinked
│   │   │   ├── dev01
│   │   │   │   ├── aks.yaml
│   │   │   │   ├── control-plane.yaml
│   │   │   │   ├── data-plane.yaml
│   │   │   │   |── cdn.yaml
│   │   │   │   ├── eks.yaml
│   │   │   │   ├── env.yaml
│   │   │   │   ├── feature_flags.yaml                                       # infrastructure related
│   │   │   │   ├── istio.yaml
│   │   │   │   ├── rds.yaml
│   │   ├── hosts
│   │   ├── user1
│   │   │   ├── group_vars
│   │   │   │   ├── DEV -> ../../../../group_vars/DEV/
│   │   │   │   ├── dev02 -> ../../group_vars/dev02/
│   │   │   │   └── user1
│   │   │   │       ├── control-plane.yaml
│   │   │   │       ├── data-plane.yaml
│   │   │   │       ├── feature_flags.yaml                                   # app related
│   │   │   │       ├── product_management.yaml
│   │   │   │       ├── release.yaml
│   │   │   │       ├── user_onboarding.yaml
│	│	│	│		└── vault_dev02_user1_secrets.yaml                       # encrypted
│   │	│	└── hosts
└── hosts
├── group_vars
│   ├── all
│   │   ├── all.yaml
│   ├── DEV
│   │   ├── aks.yaml
│   │   ├── eks.yaml
│   │   ├── apigw.yaml
│   │   ├── cdn.yaml
│   │   ├── msk.yaml
│   │   ├── rds.yaml
│   │   ├── vault.yaml                                                      # encrypted
#...omitted for brevity
```

### solving for duplication

to enable inheritance/overrides and solve duplication, below was the `hosts` file in our ansible inventory

the below shows the clear hierarchy or merging of variables happening as per the parent-child model:  `all->DEV -> dev01 -> user1`

this means:

- DEV -> account level configs defined here (infra)
- dev01 -> env level configs defined here (infra)
- user1 -> user specific customizations defined here (app/release)

```yaml
# NOTE: some values are marked <redacted> due to the sensitive nature of the enterprise env
# inventories/DEV/dev01/user1/hosts
---
all:
  hosts:
    deploy_host_local:
      ansible_connection: local
    deploy_host_local_east_1:
      ansible_connection: local
    <redacted>_host:
      ansible_host: <redacted>
      ansible_hostname: <redacted>
      ansible_connection: ssh
      ansible_user: "{{ vault_<redacted>_remote_host_username }}"
      ansible_become_method: sudo
      ansible_become_password: "{{ vault_<redacted>_remote_host_password }}"
      ansible_ssh_private_key_file: /tmp/<redacted>-vm-pvt.key
    <redacted>_host:
      ansible_host: <redacted>
      ansible_connection: ssh
      ansible_user: "{{ vault_<redacted>_host_username }}"
      ansible_become: yes
      ansible_become_method: sudo
      ansible_become_password: "{{ vault_<redacted>_host_password }}"
      ansible_ssh_private_key_file: "{{ local_decrypt_private_key_file }}"
  children:
    DEV:
      children:
        dev01:
          children:
            user1:
              hosts:
                deploy_host_local:
                deploy_host_local_east_1:
                <redacted>_host:
                <redacted>_host:
  vars:
    ansible_python_interpreter: /usr/bin/env python3

```

### converged configuration

convergence of configuration came out as a side effect of the `inventory/hosts` pattern that was gave with `parent/child` relationship

ansible merges configuration finally at [per host level](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html#inheriting-variable-values-group-variables-for-groups-of-groups) which you specify in your `tasks` file which can be observed as below

```json
// DEV -> ACCOUNT LEVEL CONFIGURATION
// ansible-inventory -i inventories/DEV --host deploy_host_local
{
// ...omitted for brevity
1588   │     "appspaces": [
1589   │         "user1",
1590   │         "user2",
1591   │         "user3",
1592   │         //... omitted for brevity
1610   │     ],
1611   │     "aws_account_number": ""<redacted>",
1612   │     "aws_backup_region": "{{ aws_region }}",
1613   │     "aws_region": "us-east-1",
1614   │     "aws_secretsmanager_secret_cert_body": "{{ application | lower }}-tls-cert-cert-body-{{ aws_region }}-{{ env_instance }}",
1615   │     "aws_secretsmanager_secret_pvt_key": "{{ application | lower }}-tls-cert-pvt-key-{{ aws_region }}-{{ env_instance }}",
1616   │     "aws_sns_developers_topic_name": "",
1617   │     "aws_sns_devops_and_devs_topic_name": "",
1618   │     "aws_sns_devops_topic_name": "",
1619   │     "aws_subnet_ids": [
1620   │         "subnet-0b...<redacted>",
1621   │         "subnet-07...<redacted>"
1622   │     ],
1623   │     "aws_vpc_cidr": "<redacted>",
1624   │     "aws_vpc_id": "vpc-000....",
// ...omitted for brevity
}

// DEV/dev01 -> ACCOUNT LEVEL + ENV LEVEL (inherit/override)
// ansible-inventory -i inventories/DEV/dev01 --host deploy_host_local
{
// ...omitted for brevity
51   │     "aks_cluster_name": "{{ application | lower }}-aks-{{ azure_location }}-{{ env }}",
52   │     "aks_cluster_version": "1.34",
53   │     "aks_kube_config": "{{ aks_info['aks'][0]['kube_config'][0] }}",
54   │     "aks_kubeconfig_filename": "/tmp/{{ aks_cluster_name }}",
55   │     "aks_nodes_count": 1,
56   │     "aks_nodes_max_count": 10,
57   │     "aks_nodes_max_surge": "33%",
// ...omitted for brevity
}

// DEV/dev01/user1 -> ACCOUNT LEVEL + ENV LEVEL + USER LEVEL (inherit/override)
// ansible-inventory -i inventories/DEV/dev01/user1 --host deploy_host_local 
{
// omitted for brevity
27   │     "feature_flags_enable_test_feature_2": true,
29   │     "feature_flags_enable_test_feature_1": true,
30   │     "feature_flags_enable_cdc": false,
35   │     "feature_flags_enable_open_telemetry": false,
// omitted for brevity
}
```

### flattening the config

nested configuration being difficult to modify, gave rise to flattened config variable naming which is relevant from the above examples already

```yaml
---
# use this
aws_vpc_cidr: <value>
# instead of
aws:
  vpc:
    cidr: <value>
# ... and so on
```

## how it scaled

well, given the structure and pattern was in place, rest worked automatically for us as per the `playbooks/roles/tasks` approach of `ansible`

given all magic is in the inventory pattern to allow hierarchical configuration model, as long as you can invoke your playbooks and roles within them, everything just works together with ease

now in the playbooks, you could define specific stacks together to be provisioned in a chain

```shell
# INFRA STACKS
# ansible-playbook -i inventories/DEV playbooks/stacks/control-plane/databases.yaml
---
- import_playbook: ../../playbooks/aws/rds/create.yml
- import_playbook: ../../playbooks/aws/...
- import_playbook: ../../playbooks..
# .. omitted for brevity

# INFRA SERVICES
# Provisioning infra (DEV)
# ansible-playbook -i inventories/DEV/ playbooks/aws/vpc/create.yml

# Provisioning/Configuring Infra (dev01)
# ansible-playbook -i inventories/DEV/dev01 playbooks/aws/eks/create.yml

# Deploying app (user1)
# ansible-playbook -i inventories/DEV/dev01/user1 playbooks/aws/control-plane/create.yml
```

## value additions

✅ no config sprawl

✅ clear distinction of account/env/user in hierarchical fashion

✅ easy debug with standard command -> `ansible-inventory`

✅ parallelism per host at playbook level and is configurable

✅ great flexibility with blocks of infrastructure+app forming `stacks` that can be switched in/out with ease as needed

✅ easy to modify, add any configuration

✅ simple to enable self-service workflows for devX targeting specific stacks in a 1-click fashion

✅ works well for a mix of brownfield and greenfield application/infrastructure where both declarative and imperative approach is needed

## trade offs

✖️ yaml sprawl -> given `ansible` is at the center of orchestration/config management, there is lot of yaml which might become overwhelming at times

✖️ pattern retrofitting -> the pattern is custom retrofitted through experience and expertise and doesn't apply/work out of the box

✖️ deploy hosts -> given `ansible` works at host level a specific host machine is needed per region for deployments with prerequisites setup

✖️ cicd -> CICD for infra would add complexity for non-declarative workflows (diffs would be hard to observe proposed changes)

overall, it has been a roller coaster ride through the trenches and finally finding a deeply fulfilling pattern that worked for us at scale. its not perfect but it brought us to a much better place than what we were in the beginning with trade-offs that we have the appetite to digest

✌️
