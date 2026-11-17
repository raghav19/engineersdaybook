#!/usr/bin/env bash
# Install the Fresh packages listed in ~/.config/fresh/plugins.list, pinned to commits.
set -euo pipefail

cfg="${FRESH_CONFIG_DIR:-$HOME/.config/fresh}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

while read -r kind name repo commit subdir; do
  [[ -z $kind || $kind == \#* ]] && continue

  case $kind in
    plugin | language | theme) dest_root="$cfg/${kind}s/packages" ;;
    *) echo "skip $name: unknown kind '$kind'" >&2; continue ;;
  esac

  src="$tmp/$name"
  git init -q "$src"
  git -C "$src" fetch -q --depth 1 "$repo" "$commit"
  git -C "$src" checkout -q FETCH_HEAD

  mkdir -p "$dest_root"
  rm -rf "${dest_root:?}/$name"
  cp -r "$src/${subdir:-.}" "$dest_root/$name"
  rm -rf "$dest_root/$name/.git"

  echo "ok  $kind $name @ ${commit:0:7}"
done < "$cfg/plugins.list"
