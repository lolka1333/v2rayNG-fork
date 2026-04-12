#!/bin/bash
# Fix git symlinks that were cloned as text files on Windows
# Must be run before building

set -o errexit
set -o pipefail

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find all git-tracked symlink files (mode 120000) in a submodule dir
# and replace the text-file stub with the actual file content
resolve_symlinks_in_submodule() {
  local submodule_dir="$1"
  echo "  Resolving symlinks in: $submodule_dir"

  pushd "$submodule_dir" > /dev/null

  # git ls-files -s lists: <mode> <hash> <stage>\t<file>
  git ls-files -s | grep "^120000" | while IFS=$'\t' read -r _ file_path; do
    local abs_file="$submodule_dir/$file_path"
    local file_dir
    file_dir="$(dirname "$abs_file")"

    # A Windows symlink stub is a single line containing a relative path (../... or ./...)
    # If the file has more than one line or doesn't start with ./ or ../ — already resolved
    local line_count
    line_count="$(wc -l < "$abs_file")"
    local first_line
    first_line="$(head -1 "$abs_file")"
    if [[ $line_count -gt 1 ]] || [[ "$first_line" != ../* && "$first_line" != ./* ]]; then
      echo "    Already resolved: $file_path"
      continue
    fi

    local target_rel="$first_line"
    local target_abs
    target_abs="$(cd "$file_dir" && realpath -m "$target_rel")"

    if [[ -f "$target_abs" ]]; then
      cp "$target_abs" "$abs_file"
      echo "    Fixed: $file_path -> $target_rel"
    else
      echo "    WARNING: target not found for $file_path -> $target_rel"
    fi
  done

  popd > /dev/null
}

echo "=== Fixing Windows symlinks in submodules ==="

resolve_symlinks_in_submodule "$__dir/hev-socks5-tunnel/third-part/hev-task-system"
resolve_symlinks_in_submodule "$__dir/hev-socks5-tunnel/third-part/yaml"
resolve_symlinks_in_submodule "$__dir/hev-socks5-tunnel/src/core"

echo "=== All symlinks resolved ==="
