#!/bin/zsh
set -euo pipefail

source_app="${1:-}"
destination_app="/Applications/sui.app"

if [[ -z "$source_app" || ! -d "$source_app" ]]; then
  print -u2 "usage: $0 /path/to/sui.app"
  exit 64
fi

staging_dir="$(/usr/bin/mktemp -d /Applications/.sui-install.XXXXXX)"
staged_app="$staging_dir/sui.app"
previous_app="$staging_dir/previous-sui.app"
trap '/bin/rm -rf "$staging_dir"' EXIT

/usr/bin/ditto "$source_app" "$staged_app"
if [[ -d "$destination_app" ]]; then
  /bin/mv "$destination_app" "$previous_app"
fi
if ! /bin/mv "$staged_app" "$destination_app"; then
  if [[ -d "$previous_app" ]]; then
    /bin/mv "$previous_app" "$destination_app"
  fi
  exit 1
fi

source_extension="$source_app/Contents/PlugIns/sui Browser Bridge.appex"
installed_extension="$destination_app/Contents/PlugIns/sui Browser Bridge.appex"
if [[ -d "$source_extension" ]]; then
  /usr/bin/pluginkit -r "$source_extension" >/dev/null 2>&1 || true
fi
if [[ -d "$installed_extension" ]]; then
  /usr/bin/pluginkit -a "$installed_extension" >/dev/null 2>&1 || true
fi

print "Installed $destination_app"
