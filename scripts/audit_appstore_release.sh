#!/usr/bin/env bash
set -euo pipefail

# Audits the actual .xcarchive payload that App Store Connect will see.
# Usage:
#   scripts/audit_appstore_release.sh                         # latest local Xcode archive
#   scripts/audit_appstore_release.sh /path/to/App.xcarchive
#   scripts/audit_appstore_release.sh /path/to/claw-ios        # source tree sanity check

read_plist() {
  local plist="$1" key="$2"
  if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
  else
    awk -v key="$key" '
      $0 ~ "<key>" key "</key>" { getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit }
    ' "$plist" 2>/dev/null || true
  fi
}

latest_archive() {
  local archives_dir="$HOME/Library/Developer/Xcode/Archives"
  [[ -d "$archives_dir" ]] || return 1
  local archives=()
  while IFS= read -r -d '' archive; do
    archives+=("$archive")
  done < <(find "$archives_dir" -type d -name '*.xcarchive' -print0 2>/dev/null)
  [[ ${#archives[@]} -gt 0 ]] || return 1
  ls -td "${archives[@]}" 2>/dev/null | head -1
}

audit_archive() {
  local archive="$1"
  echo "Archive: $archive"
  echo
  local failed=0 found=0
  while IFS= read -r -d '' plist; do
    found=1
    local bundle id short build
    bundle="${plist#$archive/Products/Applications/}"
    bundle="${bundle%/Info.plist}"
    id="$(read_plist "$plist" CFBundleIdentifier)"
    short="$(read_plist "$plist" CFBundleShortVersionString)"
    build="$(read_plist "$plist" CFBundleVersion)"
    printf '%-72s  id=%-32s  version=%-8s  build=%s\n' "$bundle" "$id" "$short" "$build"
    if [[ "$short" == "1.0.0" || "$short" == "1.0" || -z "$short" ]]; then
      failed=1
    fi
  done < <(find "$archive/Products/Applications" -name Info.plist -print0 2>/dev/null)

  if [[ "$found" -eq 0 ]]; then
    echo "ERROR: no app bundle Info.plists found in archive" >&2
    exit 2
  fi

  echo
  if [[ "$failed" -eq 0 ]]; then
    echo "PASS: archive does not contain stale 1.0.0/1.0 bundle versions."
  else
    echo "FAIL: archive still contains stale 1.0.0/1.0 bundle versions." >&2
    echo "You are uploading a stale archive or building from a stale generated project." >&2
    exit 1
  fi
}

audit_source() {
  local dir="$1"
  echo "Source tree: $dir"
  echo
  local failed=0
  echo "Version/build references:"
  grep -R "CFBundleShortVersionString\|CFBundleVersion\|MARKETING_VERSION\|CURRENT_PROJECT_VERSION" -n \
    "$dir/project.yml" "$dir"/*/Info.plist 2>/dev/null || true
  echo
  if grep -R "CFBundleShortVersionString: \"1\.0\.0\"\|<string>1\.0\.0</string>\|CFBundleVersion: \"1\"\|<key>CFBundleVersion</key>[[:space:]]*<string>1</string>" -n \
    "$dir/project.yml" "$dir"/*/Info.plist 2>/dev/null; then
    failed=1
  fi
  if [[ -f "$dir/Claw/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" ]]; then
    file "$dir/Claw/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" || true
  fi
  echo
  if [[ "$failed" -eq 0 ]]; then
    echo "PASS: source tree has no obvious stale release version refs."
  else
    echo "FAIL: source tree still has stale release refs." >&2
    exit 1
  fi
}

target="${1:-}"
if [[ -z "$target" ]]; then
  target="$(latest_archive || true)"
  if [[ -z "$target" ]]; then
    echo "ERROR: no Xcode archives found. Pass a .xcarchive path or source dir." >&2
    exit 2
  fi
fi

if [[ "$target" == *.xcarchive || -d "$target/Products/Applications" ]]; then
  audit_archive "$target"
elif [[ -d "$target" ]]; then
  audit_source "$target"
else
  echo "ERROR: target not found: $target" >&2
  exit 2
fi
