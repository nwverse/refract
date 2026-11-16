#!/bin/bash
# Merge a PR only after the privacy scan passes on what it changes (CLAUDE.md, "Development workflow"):
#   scripts/hooks/merge-pr.sh <PR number>
# Reads the PR once, scans its commits on top of its base and the squash commit's message (`<title> (#N)` and the
# body) with this machine's private values, then squash-merges exactly the head it scanned and deletes the branch.
# Hosted CI cannot do this: it does not have the values.
set -euo pipefail
pr="${1:?usage: scripts/hooks/merge-pr.sh <PR number>}"
case "$pr" in *[!0-9]*) echo "merge-pr: not a PR number: $pr" >&2; exit 2 ;; esac
root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/merge-pr.XXXXXX")"
trap 'rm -rf "${tmp:?}"' EXIT
gh pr view "$pr" --json headRefOid,headRefName,isCrossRepository,baseRefName,title,body > "$tmp/pr.json"
python3 - "$tmp" "$pr" <<'PY'
import json, re, sys
tmp, pr = sys.argv[1:]
v = json.load(open(tmp + "/pr.json", encoding="utf-8"))
head, branch, base, title, body = (v.get(k) for k in ("headRefOid", "headRefName", "baseRefName", "title", "body"))
if not (all(isinstance(r, str) and re.fullmatch(r"\S+", r) for r in (head, branch, base))
        and isinstance(title, str) and isinstance(body, str)):
    sys.exit("merge-pr: unexpected PR fields from gh pr view")
subject = "%s (#%s)" % (title, pr)
same_repo = "" if v.get("isCrossRepository") else "yes"
files = {"fields": "".join(line + "\n" for line in (head, branch, same_repo, base)), "subject": subject,
         "body": body, "message": subject + "\n\n" + body}
for name, text in files.items():
    with open(tmp + "/" + name, "w", encoding="utf-8", newline="") as out:
        out.write(text)
PY
{ IFS= read -r head; IFS= read -r branch; IFS= read -r same_repo; IFS= read -r base; } < "$tmp/fields"
subject="$(<"$tmp/subject")"
git -C "$root" fetch -q origin "refs/heads/$base"
base_sha="$(git -C "$root" rev-parse FETCH_HEAD)"
git -C "$root" fetch -q origin "pull/$pr/head"
[ "$(git -C "$root" rev-parse FETCH_HEAD)" = "$head" ] || { echo "merge-pr: the PR moved while fetching; run it again" >&2; exit 1; }
python3 "$root/scripts/privacy_check.py" --range "$base_sha..$head" --message "$tmp/message" \
  || { echo "merge-pr: #$pr not merged: fix the hits above in the PR first" >&2; exit 1; }
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
# From outside the repository, by name: gh then only merges on GitHub and never checks out the base in a worktree.
(cd / && gh pr merge "$pr" --repo "$repo" --squash --match-head-commit "$head" \
  --subject "$subject" --body-file "$tmp/body")
if [ -n "$same_repo" ] && gh api "repos/$repo/git/ref/heads/$branch" >/dev/null 2>&1; then
  gh api -X DELETE "repos/$repo/git/refs/heads/$branch" >/dev/null 2>&1 || echo "merge-pr: merged; could not delete the branch $branch" >&2
fi
echo "merge-pr: #$pr merged"
