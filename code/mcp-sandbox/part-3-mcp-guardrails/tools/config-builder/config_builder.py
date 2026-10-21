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
        - the flag of a component (<folder>_enabled, for each folder with flux/stack.yaml) is a known name, and a boolean
"""

import sys
from pathlib import Path

import typer
import yaml

app = typer.Typer(add_completion=False)


def placement_folders(config_dir: Path, placement: str) -> list[Path]:
    """Return the folders to read, top down: config/, then config/cloud/, config/cloud/aws/, ... along the placement."""
    folders = [config_dir]
    for part in placement.split("/"):
        folders.append(folders[-1] / part)
    return folders


def display_path(file: Path, root: Path) -> Path:
    """Return a file as messages show it: relative to the folder that holds config/."""
    return file.relative_to(root)


def merge_file(file: Path, set_here: dict[str, Path], config: dict[str, object], source: dict[str, Path], root: Path) -> None:
    """Merge the names of one file into config. Overwrite a name set before, and print that."""
    for name, value in (yaml.safe_load(file.read_text()) or {}).items():
        if isinstance(value, (dict, list)):
            sys.exit(f"{display_path(file, root)}: {name} is not a plain value (config is flat: name: value)")
        if name in set_here:
            sys.exit(f"{name} is set in both {display_path(set_here[name], root)} and {display_path(file, root)}: same level, no winner")
        if name in source:
            print(f"  {name}: {display_path(source[name], root)} -> {display_path(file, root)}")
        set_here[name] = source[name] = file
        config[name] = value


def merge_level(folder: Path, config: dict[str, object], source: dict[str, Path], root: Path) -> None:
    """Merge every *.yaml of one level, in name order."""
    set_here: dict[str, Path] = {}  # name -> file, for this level only: two files of one level must not set one name
    for file in sorted(folder.glob("*.yaml")):
        print(f"config: {display_path(file, root)}")
        merge_file(file, set_here, config, source, root)


def collect_setter_names(root: Path) -> set[str]:
    """Return every name that some setters.yaml lists (copies under out/ are skipped)."""
    known: set[str] = set()
    for file in root.rglob("setters.yaml"):
        if "out" not in display_path(file, root).parts:
            known |= set(yaml.safe_load(file.read_text()) or {})
    return known


def collect_flag_names(root: Path) -> set[str]:
    """Return the flag of every switchable component: <folder>_enabled for each folder that has flux/stack.yaml."""
    return {
        entry.parent.parent.name.replace("-", "_") + "_enabled"
        for entry in root.rglob("flux/stack.yaml")
        if "out" not in display_path(entry, root).parts
    }


def reject_non_boolean_flags(config: dict[str, object], source: dict[str, Path], flags: set[str], root: Path) -> None:
    """Exit on a component flag that is not true or false: the string "false" is not a boolean."""
    for name in flags & config.keys():
        if not isinstance(config[name], bool):
            sys.exit(f"{display_path(source[name], root)}: {name} is {config[name]!r}, it must be true or false (a YAML boolean)")


def reject_unknown_names(config: dict[str, object], source: dict[str, Path], known: set[str], root: Path) -> None:
    """Exit on a name that no setters.yaml lists: nothing would use it (a misspelt override)."""
    for name in config:
        if name not in known:
            sys.exit(f"{display_path(source[name], root)}: {name} is not in any setters.yaml, so nothing would use it (misspelt?)")


def write_values_file(config: dict[str, object], source: dict[str, Path], output_file: Path, root: Path) -> None:
    """Write one line per name, the file it came from as a trailing comment."""
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with output_file.open("w") as out:
        for name, value in config.items():
            out.write(f"{yaml.safe_dump({name: value}).rstrip()}  # {display_path(source[name], root)}\n")


@app.command()
def main(config_dir: Path, cluster_file: Path, output_file: Path) -> None:
    root = config_dir.parent
    placement = yaml.safe_load(cluster_file.read_text())["placement"]

    config: dict[str, object] = {}  # the result: name -> value, a lower level overwrites
    source: dict[str, Path] = {}  # name -> the file that set the value now in config
    for folder in placement_folders(config_dir, placement):
        merge_level(folder, config, source, root)

    flags = collect_flag_names(root)
    reject_unknown_names(config, source, collect_setter_names(root) | flags, root)
    reject_non_boolean_flags(config, source, flags, root)
    write_values_file(config, source, output_file, root)


if __name__ == "__main__":
    app()
