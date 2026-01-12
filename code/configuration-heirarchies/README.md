# configuration heirarchies

this repo gives a sample of the configuration heirarchy pattern that we used to scale our infra code base for our app. blog post ->

## structure
```text
.
├── inventories
│   ├── DEV
│   │   └── dev01
│   │       ├── group_vars
│   │       │   ├── DEV -> ../../../group_vars/DEV/
│   │       │   └── dev01
│   │       │       ├── db.yaml
│   │       │       └── eks.yaml
│   │       ├── hosts
│   │       └── user1
│   │           ├── group_vars
│   │           │   ├── DEV -> ../../../../group_vars/DEV/
│   │           │   ├── dev01 -> ../../group_vars/dev01/
│   │           │   └── user1
│   │           │       └── feature_flags.yaml
│   │           └── hosts
│   ├── group_vars
│   │   ├── aws_us_east_1_pre_account
│   │   │   └── common.yaml
│   │   ├── aws_us_east_1_prod_account
│   │   │   └── common.yaml
│   │   ├── aws_us_east_2_pre_account
│   │   │   └── common.yaml
│   │   ├── aws_us_east_2_prod_account
│   │   │   └── common.yaml
│   │   ├── DEV
│   │   │   └── eks.yaml
│   │   ├── PRE
│   │   │   └── eks.yaml
│   │   └── PROD
│   │       ├── eks.yaml
│   │       └── feature_flags.yaml
│   ├── PRE
│   │   └── pre01
│   │       ├── group_vars
│   │       │   ├── PRE -> ../../../group_vars/PRE/
│   │       │   └── pre01
│   │       │       └── feature_flags.yaml
│   │       └── hosts
│   └── PROD
│       └── prod
│           ├── group_vars
│           │   └── PROD -> ../../../group_vars/PROD/
│           └── hosts
├── playbooks
├── README.md
└── roles
```

## how the heirarchy works
- Dev env:  DEV -> dev01 -> user1
- Pre env: PRE -> pre01
- Prod env: Prod -> prod

## how to view the inheritance of vars

- ensure to have ansible installed 

- clone/fork the repo and navigate to `./code/configuration-heirarchies`

- for `DEV -> dev01`:
```shell
ansible-inventory -i inventories/DEV/dev01/hosts --host deploy_host_local
# output:
# {
#     "ansible_connection": "local",
#     "ansible_python_interpreter": "/usr/bin/env python3",
#     "eks_cluster_version": "1.34",
#     "eks_k8s_version": "1.34",
#     "eks_network_calico_version": "3.31.2",
#     "eks_nodes_ami_type": "AL2023_x86_64_STANDARD",
#     "eks_nodes_instance_types": [
#         "m7i-flex.xlarge"
#     ],
#     "eks_nodes_version": "1.34",
#     "eks_ssm_parameter_name": "/aws/service/eks/optimized-ami/{{ eks_cluster_version }}/amazon-linux-2023/x86_64/standard/recommended/release_version",
#     "rds_allocated_storage": 32,
#     "rds_engine_version": "15.7",
#     "rds_max_allocated_storage": 64,
#     "rds_parameter_group_family": "postgres15"
# }
```

- for `DEV -> dev01 -> user1`:
```shell
ansible-inventory -i inventories/DEV/dev01/user1/hosts --host deploy_host_local

# NOTES:
# - notice 2 vars: feature_flags_enable_feature_x, feature_flags_enable_feature_y got added into the list

# output:
# {
#     "ansible_connection": "local",
#     "ansible_python_interpreter": "/usr/bin/env python3",
#     "eks_cluster_version": "1.34",
#     "eks_k8s_version": "1.34",
#     "eks_network_calico_version": "3.31.2",
#     "eks_nodes_ami_type": "AL2023_x86_64_STANDARD",
#     "eks_nodes_instance_types": [
#         "m7i-flex.xlarge"
#     ],
#     "eks_nodes_version": "1.34",
#     "eks_ssm_parameter_name": "/aws/service/eks/optimized-ami/{{ eks_cluster_version }}/amazon-linux-2023/x86_64/standard/recommended/release_version",
#     "feature_flags_enable_feature_x": false,
#     "feature_flags_enable_feature_y": false,
#     "rds_allocated_storage": 32,
#     "rds_engine_version": "15.7",
#     "rds_max_allocated_storage": 64,
#     "rds_parameter_group_family": "postgres15"
# }
```

- for `PRE -> pre01`
```shell
ansible-inventory -i inventories/PRE/pre01/hosts --host deploy_host_aws_us_east_1
# output
# {
#     "ansible_connection": "local",
#     "ansible_python_interpreter": "/usr/bin/env python3",
#     "eks_cluster_version": "v2",
#     "eks_k8s_version": "1.33",
#     "feature_flags_enable_feature_x": false,
#     "feature_flags_enable_feature_y": true
# }
```

- for `PROD -> prod`
```shell
ansible-inventory -i inventories/PROD/prod/hosts --host deploy_host_aws_us_east_1
# output:
# {
#     "ansible_connection": "local",
#     "ansible_python_interpreter": "/usr/bin/env python3",
#     "eks_cluster_version": "v2",
#     "eks_k8s_version": "1.33",
#     "feature_flags_enable_feature_x": true,
#     "feature_flags_enable_feature_y": true
# }
```

## how to view the parent-child relationship
```shell
ansible-inventory -i inventories/DEV/dev01/hosts --list
ansible-inventory -i inventories/DEV/dev01/user1/hosts --list
ansible-inventory -i inventories/PRE/pre01/hosts --list
ansible-inventory -i inventories/PROD/prod/hosts --list

# output
# {
#     "PRE": {
#         "children": [
#             "pre01"
#         ]
#     },
#     "_meta": {
#         "hostvars": {
#             "deploy_host_aws_us_east_1": {
#                 "ansible_connection": "local",
#                 "ansible_python_interpreter": "/usr/bin/env python3",
#                 "eks_cluster_version": "v2",
#                 "eks_k8s_version": "1.33",
#                 "feature_flags_enable_feature_x": false,
#                 "feature_flags_enable_feature_y": true
#             },
#             "deploy_host_aws_us_east_2": {
#                 "ansible_connection": "local",
#                 "ansible_python_interpreter": "/usr/bin/env python3",
#                 "eks_cluster_version": "v2",
#                 "eks_k8s_version": "1.33",
#                 "feature_flags_enable_feature_x": false,
#                 "feature_flags_enable_feature_y": true
#             }
#         }
#     },
#     "all": {
#         "children": [
#             "ungrouped",
#             "PRE"
#         ]
#     },
#     "aws_us_east_1_pre_account": {
#         "hosts": [
#             "deploy_host_aws_us_east_1"
#         ]
#     },
#     "aws_us_east_2_pre_account": {
#         "hosts": [
#             "deploy_host_aws_us_east_2"
#         ]
#     },
#     "pre01": {
#         "children": [
#             "aws_us_east_1_pre_account",
#             "aws_us_east_2_pre_account"
#         ]
#     }
# }
```

## at what levels is variables can be placed

- DEV account
```text
# NOTE: 
- this means the vars are inherited from DEV -> dev01 -> user1 where it allows users to set only required vars at each level

DEV   -> vars for account level
dev01 -> vars for dev01 env
user1 -> vars for dev01/user1 env
```

- PRE account
```text
# NOTE: 
- this means the vars are inherited from PRE -> pre01 where it allows users to set only required vars at each level

PRE   -> vars for account level
pre01 -> vars for pre01 env
```

- PROD account
```text
# NOTE: 
- this means the vars are inherited from PROD -> prod where it allows users to set only required vars at each level

PROD -> vars for account level
prod -> vars for prod env
```