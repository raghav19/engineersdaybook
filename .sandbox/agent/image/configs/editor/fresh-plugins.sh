#!/usr/bin/env bash
# Install the Fresh packages of fresh-plugins.yaml at their pinned commits. The mise task fresh:plugins runs this script.
# A test can set FRESH_CONFIG_DIR to use another folder.
set -euo pipefail

cfg="${FRESH_CONFIG_DIR:-$HOME/.config/fresh}"
list="$cfg/fresh-plugins.yaml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# field NAME prints one field of the package in $name. Example: field repo.
field() { yq ".\"$name\".$1" "$list"; }

yq 'keys | .[]' "$list" | while read -r name; do
  commit=$(field commit)
  # The kind gives the folder: plugin to plugins/packages, language to languages/packages, theme to themes/packages.
  dest="$cfg/$(field kind)s/packages/$name"

  # The file .commit holds the commit of the last install. If it is the pinned commit, skip the package.
  if [ "$(cat "$dest/.commit" 2>/dev/null)" = "$commit" ]; then
    echo "ok  $name (installed)"
    continue
  fi

  # Fetch only the pinned commit, with no history. It needs a full hash and no tag.
  git -C "$tmp" init -q "$name"
  git -C "$tmp/$name" fetch -q --depth 1 "$(field repo)" "$commit"
  git -C "$tmp/$name" checkout -q FETCH_HEAD

  # A monorepo has more than one package, so copy the subdir and not the repo.
  rm -rf "$dest"
  mkdir -p "${dest%/*}"
  cp -r "$tmp/$name/$(field subdir)" "$dest"
  rm -rf "$dest/.git"
  echo "$commit" >"$dest/.commit"
  echo "ok  $name (installed now)"
done
