#!/usr/bin/env bash
# Prints the paths that changed between BASE and HEAD, one per line
# (ci.yml, job "changes"). Exits non-zero if the diff cannot be made.
#
# - --no-renames: a moved file is listed under both its old and its new path,
#   so that moving a file out of lib/ or spike/ still runs those jobs.
# - core.quotePath=false: paths with å, ä, ö are printed as they are, not as
#   quoted octal escapes that the patterns in changed-jobs.sh would miss.
set -euo pipefail
base="${1:?usage: changed-files.sh BASE}"
git -c core.quotePath=false diff --no-renames --name-only "$base" HEAD
