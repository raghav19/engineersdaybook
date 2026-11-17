#!/usr/bin/env bash
# Install the Fresh packages of plugins.list at their pinned commits. A line is: kind name repo commit [subdir]. The kind is plugin, language or theme.
# A package keeps the file .commit. If it holds the commit of the list, the script does not fetch the package again.
set -euo pipefail

cfg="${FRESH_CONFIG_DIR:-$HOME/.config/fresh}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

while read -r kind name repo commit subdir; do
  case $kind in '' | '#'*) continue ;; esac
  dest="$cfg/${kind}s/packages/$name"

  if [ -f "$dest/.commit" ] && [ "$(cat "$dest/.commit")" = "$commit" ]; then
    echo "ok  $kind $name (installed)"
    continue
  fi

  git -C "$tmp" init -q "$name"
  git -C "$tmp/$name" fetch -q --depth 1 "$repo" "$commit"
  git -C "$tmp/$name" checkout -q FETCH_HEAD

  rm -rf "$dest"
  mkdir -p "$cfg/${kind}s/packages"
  cp -r "$tmp/$name/${subdir:-.}" "$dest"
  rm -rf "$dest/.git"
  echo "$commit" >"$dest/.commit"
  echo "ok  $kind $name (installed now)"
done <"$cfg/plugins.list"
