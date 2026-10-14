"""Put the converged values into the manifests of one component folder.

usage: value_injector.py <values.yaml> <component folder> <output folder>

<component folder>/setters.yaml says which value goes to which field. One shape for every kind of object:

    <value name>:
      - object: <Kind>/<name>        # HelmRelease/spire, Gateway/agentgateway-proxy, Kustomization (no name: kustomization.yaml)
        path: <dotted path>          # a number is a position in a list; for a chart value start at spec.values

A value in the config overrides the field. Without one, the field keeps what the manifest holds: that is its default. A field the
manifest does not hold has no default: its value is required, and the build fails without it.
"""
import re
import shutil
import sys
from pathlib import Path

import yaml


def keys_of(path):
    """spec.listeners.0.port -> ['spec', 'listeners', 0, 'port']   (\\. is a dot inside a key)"""
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

shutil.copytree(src, dst, dirs_exist_ok=True)  # work on a copy; the source is never edited

applied = set()
written = {}  # (object, path) -> the value name that sets it
for manifest in Path(dst).glob("*.yaml"):
    docs = list(yaml.safe_load_all(manifest.read_text()))
    for doc in filter(None, docs):
        for name, targets in setters.items():  # each value name
            for target in targets:  # each field it goes to
                kind, _, obj = target["object"].partition("/")
                if doc.get("kind") == kind and (not obj or doc.get("metadata", {}).get("name") == obj):
                    field = (target["object"], target["path"])
                    applied.add((name, target["object"]))
                    if name not in values:  # no override: the manifest holds the default, or the value is required
                        if not has_path(doc, target["path"]):
                            sys.exit(f"setters.yaml: {name} has no value in the config (config/, placement of the cluster), "
                                     f"and {field[0]} has no {field[1]} to default to")
                        continue
                    if field in written:
                        sys.exit(f"setters.yaml: {field[0]} {field[1]} is set by both {written[field]} and {name}")
                    written[field] = name
                    set_path(doc, target["path"], values[name])
    manifest.write_text(yaml.safe_dump_all(docs, sort_keys=False))

for name, targets in setters.items():  # every target must have been found
    for target in targets:
        if (name, target["object"]) not in applied:
            sys.exit(f"setters.yaml: {target['object']} is not in {src}")
