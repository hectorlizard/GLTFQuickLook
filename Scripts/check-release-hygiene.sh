#!/bin/bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

failed=0

if git ls-files -z | grep -zE '(^|/)\.DS_Store$' >/dev/null; then
  echo "error: a .DS_Store file is tracked"
  failed=1
fi

if git grep -nIE '(/Users/|/Volumes/|file:///)' -- \
  . \
  ':!Scripts/check-release-hygiene.sh' \
  ':!Scripts/package-release.sh'; then
  echo "error: a tracked file contains a machine-specific absolute path"
  failed=1
fi

if git grep -nIE '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|API[_-]?KEY[[:space:]]*=)' -- .; then
  echo "error: a tracked file resembles a credential"
  failed=1
fi

if (( failed != 0 )); then
  exit 1
fi

echo "Release hygiene checks passed."
