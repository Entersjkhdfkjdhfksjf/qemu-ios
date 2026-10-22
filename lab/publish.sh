#!/usr/bin/env bash
# usage: publish.sh <dir-name-on-ci-logs> <file>...   (text logs only)
set +e
DEST="$1"; shift
URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
for i in 1 2 3 4 5 6; do
  rm -rf /tmp/cil
  git clone --depth 1 --branch ci-logs "$URL" /tmp/cil 2>/dev/null || {
    mkdir /tmp/cil; git -C /tmp/cil init -q -b ci-logs; git -C /tmp/cil remote add origin "$URL"; }
  rm -rf "/tmp/cil/$DEST"; mkdir -p "/tmp/cil/$DEST"
  for f in "$@"; do [ -f "$f" ] && cp "$f" "/tmp/cil/$DEST/"; done
  echo "run $GITHUB_RUN_ID sha $GITHUB_SHA" > "/tmp/cil/$DEST/RUN"
  (cd /tmp/cil && git add -A && git -c user.name=ci -c user.email=ci@users.noreply.github.com commit -q -m "$DEST logs run $GITHUB_RUN_ID" && git push origin HEAD:ci-logs) && exit 0
  sleep $((RANDOM % 5 + 2))
done
exit 1
