"""config-builder: merge the config hierarchy of one cluster into one flat file.

usage: config_builder.py <config dir> <cluster.yaml> <output file>

Input   the levels of config/ named by `placement` in <cluster.yaml>, top to bottom; every *.yaml of a level is read:

            placement: cloud/aws/dev   ->   config/*.yaml            global, the same on every cloud
                                            config/cloud/*.yaml
                                            config/cloud/aws/*.yaml
                                            config/cloud/aws/dev/*.yaml

Output  <output file>: one `name: value` per line, each with the file it came from.
        Overrides only: a name that nothing sets keeps the default in the manifest of the component.

Rules   - a lower level wins over a level above it, and says so
        - the same name twice in ONE level is an error: there is no winner
        - a value is plain (`name: value`), never a map or a list
        - a name that no setters.yaml lists is an error: nothing would use it (a misspelt override)
"""
import sys
from pathlib import Path

import yaml

config_dir, cluster_file, output_file = map(Path, sys.argv[1:])
placement = yaml.safe_load(cluster_file.read_text())["placement"]

levels = [config_dir]  # one folder per level, top down: config/, config/cloud/, config/cloud/aws/, ...
for part in placement.split("/"):
    levels.append(levels[-1] / part)


def shown(file):
    return file.relative_to(config_dir.parent)


config = {}  # the result: name -> value, a lower level overwrites
source = {}  # name -> the file that set the value now in config
for level in levels:
    set_here = {}  # name -> file, for this level only: two files of one level must not set one name
    for file in sorted(level.glob("*.yaml")):
        print(f"config: {shown(file)}")
        for name, value in (yaml.safe_load(file.read_text()) or {}).items():
            if isinstance(value, (dict, list)):
                sys.exit(f"{shown(file)}: {name} is not a plain value (config is flat: name: value)")
            if name in set_here:
                sys.exit(f"{name} is set in both {shown(set_here[name])} and {shown(file)}: same level, no winner")
            if name in source:
                print(f"  {name}: {shown(source[name])} -> {shown(file)}")
            set_here[name] = source[name] = file
            config[name] = value

known = set()  # every name that some setters.yaml lists (copies under out/ are skipped)
for file in config_dir.parent.rglob("setters.yaml"):
    if "out" not in shown(file).parts:
        known |= set(yaml.safe_load(file.read_text()) or {})
for name in config:
    if name not in known:
        sys.exit(f"{shown(source[name])}: {name} is not in any setters.yaml, so nothing would use it (misspelt?)")

output_file.parent.mkdir(parents=True, exist_ok=True)
with output_file.open("w") as out:
    for name, value in config.items():  # one line per name, the file it came from as a trailing comment
        out.write(f"{yaml.safe_dump({name: value}).rstrip()}  # {shown(source[name])}\n")
