#!/usr/bin/env bash
# Install the Fresh packages of fresh-plugins.yaml at their pinned commits. The mise task fresh:plugins runs this script.
# fresh-plugins.yaml has one key for each package. The key is the name of the package. Its fields are kind, repo, commit and subdir.
# A package keeps the file .commit. If it holds the commit of the list, the script does not fetch the package again.
set -euo pipefail

# Fresh reads its packages from ~/.config/fresh. A test can set FRESH_CONFIG_DIR to use another folder.
cfg="${FRESH_CONFIG_DIR:-$HOME/.config/fresh}"
list="$cfg/fresh-plugins.yaml"
# A scratch folder for the fetches. The trap removes it when the script ends, also after an error.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# field NAME prints one field of the package in $name, for example: field repo
field() { yq ".\"$name\".$1" "$list"; }

# One turn of the loop for each key of fresh-plugins.yaml. The key is the name of the package.
yq 'keys | .[]' "$list" | while read -r name; do
  commit=$(field commit)
  # The kind gives the folder: plugin to plugins/packages, language to languages/packages, theme to themes/packages.
  dest="$cfg/$(field kind)s/packages/$name"

  # The file .commit holds the commit of the last install. If it is the pinned commit, there is nothing to do.
  if [ "$(cat "$dest/.commit" 2>/dev/null)" = "$commit" ]; then
    echo "ok  $name (installed)"
    continue
  fi

  # Fetch only the pinned commit, with no history. This works with a full hash, and it needs no tag.
  git -C "$tmp" init -q "$name"
  git -C "$tmp/$name" fetch -q --depth 1 "$(field repo)" "$commit"
  git -C "$tmp/$name" checkout -q FETCH_HEAD

  # Replace the old copy with the folder of the package. A monorepo has more than one package, so copy the subdir and not the repo.
  rm -rf "$dest"
  mkdir -p "${dest%/*}"
  cp -r "$tmp/$name/$(field subdir)" "$dest"
  # The package does not need the git data. Write the commit in .commit for the next run.
  rm -rf "$dest/.git"
  echo "$commit" >"$dest/.commit"
  echo "ok  $name (installed now)"
done
