#!/bin/sh
# For Update.qml: is this checkout behind GitHub? Prints how many commits it's missing, then
# the newest few subjects. `update.sh pull` first fast-forwards to them (refuses if that would
# clobber local edits). Fetches over HTTPS into FETCH_HEAD only: the repo is public, so no key
# or ssh-agent, and no branch of yours moves unless you pull.
cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
url=$(git remote get-url origin) || exit 1
case $url in git@github.com:*) url="https://github.com/${url#git@github.com:}" ;; esac
branch=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)
branch=${branch#*/}
GIT_TERMINAL_PROMPT=0 git fetch -q "$url" "${branch:-main}" || exit 2
if [ "$1" = pull ]; then git merge -q --ff-only FETCH_HEAD || exit 3; fi
git rev-list --count HEAD..FETCH_HEAD
git log --format=%s -5 HEAD..FETCH_HEAD
