#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml==6.0.2"]
# ///
"""Converge the config hierarchy of one cluster into one flat file.

usage: converge_config.py <config dir> <cluster.yaml> <output file>

The placement in cluster.yaml names the levels, from the top down. Every *.yaml of a level is config of that level:

    placement: aws/prod/us-east-1   ->   config/*.yaml
                                         config/aws/*.yaml
                                         config/aws/prod/*.yaml
                                         config/aws/prod/us-east-1/*.yaml

- a level further down wins over a level above it (and says so)
- two files of the SAME level setting the same name is an error: there is no winner
- every value is plain (name: value), not a map or a list
"""
import sys
from pathlib import Path

import yaml

config_dir, cluster_file, output_file = map(Path, sys.argv[1:])
placement = yaml.safe_load(cluster_file.read_text())["placement"]

levels = [config_dir]  # config/, then config/aws/, config/aws/prod/, ...
for part in placement.split("/"):
    levels.append(levels[-1] / part)


def shown(file):
    return file.relative_to(config_dir.parent)


config = {}  # name -> value
source = {}  # name -> the file that set it
for level in levels:
    set_here = {}  # name -> file, for this level only
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

output_file.parent.mkdir(parents=True, exist_ok=True)
with output_file.open("w") as out:
    for name, value in config.items():  # each value with the file it came from
        out.write(f"{yaml.safe_dump({name: value}).rstrip()}  # {shown(source[name])}\n")
