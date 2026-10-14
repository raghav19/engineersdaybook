"""value-injector: write the converged config values into the manifests of one component folder.

usage: value_injector.py <values.yaml> <component folder> <output folder>

Input   <values.yaml>                    the converged config, the output of config-builder
        <component folder>/setters.yaml  which value goes to which field, one shape for every kind of object:

            <value name>:
              - object: <Kind>/<name>    HelmRelease/spire, Gateway/agentgateway-proxy; `Kustomization` alone is kustomization.yaml
                path: <dotted path>      a number is a position in a list; a chart value starts at spec.values

Output  <output folder>: a copy of the component folder with the values set. The source folder is never edited.

Rules   - a value in the config overrides the field
        - no value: the field keeps what the manifest holds, that is its default
        - no value and no such field in the manifest: the value is required, the build fails
        - two names writing one field, or a setter whose object is not in the folder, is an error
"""

import re
import shutil
import sys
from pathlib import Path

import yaml


def keys_of(path):
    """spec.listeners.0.port -> ['spec', 'listeners', 0, 'port']   (a number is a list position, \\. is a dot inside a key)"""
    parts = [p.replace("\\.", ".") for p in re.split(r"(?<!\\)\.", path)]
    return [int(p) if p.isdigit() else p for p in parts]


def set_path(doc, path, value):
    *parents, last = keys_of(path)
    for key in parents:
        doc = doc[key] if isinstance(key, int) else doc.setdefault(key, {})
    doc[last] = value


def has_path(doc, path):
    for key in keys_of(path):
        try:
            doc = doc[key]
        except (KeyError, IndexError, TypeError):
            return False
    return True


values_file, src, dst = sys.argv[1:]
values = yaml.safe_load(Path(values_file).read_text()) or {}
setters_file = Path(src) / "setters.yaml"
setters = yaml.safe_load(setters_file.read_text()) if setters_file.exists() else {}

shutil.copytree(src, dst, dirs_exist_ok=True)  # everything below edits the copy

applied = set()  # (value name, object) pairs found in a manifest; a setter left over is an error below
written = {}  # (object, path) -> the value name that set it, to catch two names on one field
for manifest in Path(dst).glob("*.yaml"):
    docs = list(yaml.safe_load_all(manifest.read_text()))
    for doc in filter(None, docs):
        for name, targets in setters.items():  # every value name
            for target in targets:  # every field it goes to
                kind, _, obj = target["object"].partition("/")
                if doc.get("kind") == kind and (not obj or doc.get("metadata", {}).get("name") == obj):
                    field = (target["object"], target["path"])
                    applied.add((name, target["object"]))
                    if name not in values:  # no override: keep the default in the manifest, or fail when there is none
                        if not has_path(doc, target["path"]):
                            sys.exit(
                                f"setters.yaml: {name} has no value in the config (config/, placement of the cluster), "
                                f"and {field[0]} has no {field[1]} to default to"
                            )
                        continue
                    if field in written:
                        sys.exit(f"setters.yaml: {field[0]} {field[1]} is set by both {written[field]} and {name}")
                    written[field] = name
                    set_path(doc, target["path"], values[name])
    manifest.write_text(yaml.safe_dump_all(docs, sort_keys=False))

for name, targets in setters.items():  # every setter must have matched an object of the folder
    for target in targets:
        if (name, target["object"]) not in applied:
            sys.exit(f"setters.yaml: {target['object']} is not in {src}")
