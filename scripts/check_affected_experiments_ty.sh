#!/usr/bin/env bash
# Type-check the experiment projects touched by this commit, each in its own uv
# environment. Root `ty` deliberately skips experiments (their deps are not in
# the root project), so this hook is what keeps changed ones honest.
#
# pre-commit passes the staged files; each containing project is checked once.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

declare -A projects=()

for path in "$@"; do
  [[ ${path} == experiments/* ]] || continue
  dir=$(printf '%s' "${path}" | cut -d/ -f1-2)
  [[ $(basename "${dir}") =~ ^[0-9]{6}_.+ ]] || continue
  [[ -f "${dir}/pyproject.toml" ]] || continue
  projects["${dir}"]=1
done

if [[ ${#projects[@]} -eq 0 ]]; then
  echo "No affected experiment uv projects to type-check."
  exit 0
fi

for dir in $(printf '%s\n' "${!projects[@]}" | sort); do
  echo "Type-checking ${dir}"
  (cd "${dir}" && uv run --with ty ty check --output-format concise --force-exclude)
done
