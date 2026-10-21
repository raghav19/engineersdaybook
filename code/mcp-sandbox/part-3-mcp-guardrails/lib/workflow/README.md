# lib/workflow

## Files

```text
workflow.just                   the entry file: it imports the others
├── common.just                 the settings and all variables
├── package.just                package-artifact
├── diff.just                   diff
├── publish.just                publish-artifact
├── compose.just                compose-stack
└── ../../tools/tools.just      build, push
```

## What each recipe uses

```text
package-artifact
└── _manifest
    ├── _checks
    └── _stub_build
        └── _apply
            └── _config
                └── build            (tools.just)
```

```text
diff
├── _manifest                        (package.just)
└── _baseline
```

```text
publish-artifact
└── package-artifact                 (package.just)
```

```text
compose-stack
├── _config                          (package.just)
└── push                             (tools.just)
```

## Find a definition

Go to a component folder, for example `cd platform/routes`. Then run:

```bash
grep -n '^_manifest' ../../lib/workflow/*.just ../../tools/tools.just   # the file of a recipe
just --show _manifest                                                    # the source of a recipe
just --evaluate out                                                      # the value of a variable
```

To see all recipes of all files in one list, with what each one uses:

```bash
just --dump --dump-format json | jq -r '.recipes | to_entries[] | "\(.key): \(.value.dependencies | map(.recipe) | join(" "))"'
```

`just --dump` alone shows only the import line of the component.

## Rules

- Put a variable in `common.just`. Do not put it in a recipe file.
- Give each recipe a unique name. A second recipe with the same name replaces the first one without an error.
- After a change, run `package-artifact` for all components. The `out/*/manifests.yaml` files must not change.
