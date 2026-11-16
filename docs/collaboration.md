# Working with other people and Agents: claim the issue before you start

Several people and many Agents work in this repository at the same time. So: **claim the issue before you start, and
every PR links an issue**. The overall flow is in `CLAUDE.md` ("Workflow"); this page has the claim rules, comment
templates and commands you can copy.

## Rules

1. **Check for duplicates before starting**: search open issues and PRs about the same thing, and glance at recently
   closed issues and merged PRs.
2. **Someone has claimed it and the claim hasn't expired**: don't work on it. Add information under the issue with a
   comment starting `Note:`.
3. **No issue? Create one**, then post a claim comment: what you're doing, how, and how long. If an Agent does the
   work, say so. Work that affects generated output, performance or the public API adds an `Acceptance:` line naming
   the goals in `docs/GOALS.md` it touches and the evidence for each (fixtures, benchmarks, diagnostics tests).
4. **24 hours with no update counts as abandoned**: someone else may post `Take over:` with the reason. Renew with
   `Progress:`.
5. **Every PR links an issue**: `Fixes #N` / `Closes #N` / `Refs #N` in the description.
6. **Dependencies**: an issue that needs another one's result says `Depends on #N`. Until that lands, work on the parts
   that don't need it (design notes, fixtures, tests) and keep merging `origin/main`.

Don't use GitHub's assignee field or `/claim` commands: the comments in the issue are the only source of truth.

## Who is working on it

- **The owner is the GitHub account that wrote the latest `Claim:` or `Take over:`**, unless that account has posted
  `Abandon:` since. An Agent posts with the account of the person it works for, who is responsible for it.
- When an Agent does the work, the claim has `Agent: yes (<machine id> / <branch or session>)`: several Agents of one
  person share an account and are told apart by this line. Use a machine id, never a host name.
- Comments are classified by the prefix of their first line: `Claim:`, `Progress:`, `Take over:`, `Abandon:`, `Note:`.
- Two claims at almost the same time: the earlier wins. After posting, read the comments again; if yours wasn't
  first, delete it (`gh issue comment <number> --delete-last --yes`) and pick something else.

## Comment templates

```text
Claim: <what you're doing, one sentence>
Plan: <how you'll change it, which places>
ETA: <how long>
Acceptance: <goals from docs/GOALS.md this touches, and the evidence for each>
Agent: yes (<machine id> / <branch or session>)
```

```text
Progress: <how far you've got, next step, new ETA>
```

```text
Take over: claimed <time>, last update <time>, more than 24 hours ago
Plan: <how; continue from the original branch if it has usable progress>
ETA: <how long>
Agent: yes (<machine id> / <branch or session>)
```

```text
Abandon: <how far you got, what's left, where the branch / PR is>
```

```text
Note: <information for the owner>
```

## Commands

```sh
# Duplicates
gh issue list --state all --search "<keywords>"
gh pr list --state all --search "<keywords>"
git fetch origin && git log origin/main --oneline -i --grep "<keywords>" | head

# Who holds an issue
gh issue view <number> --json comments --jq '.comments[] | select(.body | test("^(Claim|Progress|Take over|Abandon):")) | "\(.createdAt)  \(.author.login)  \(.body | split("\n")[0])"'

# Create an issue (enhancement, bug or documentation)
gh issue create --title "<one sentence>" --label enhancement --body-file - <<'EOF'
## Problem
## Proposal
## Acceptance
EOF

# Claim
gh issue comment <number> --body-file - <<'EOF'
Claim: ...
Plan: ...
ETA: ...
Agent: yes (<machine id> / <branch>)
EOF
```

## Branches and PRs

```sh
git fetch origin
git worktree add .worktrees/<type>/<number>-<slug> -b <type>/<number>-<slug> origin/main
# ... work, stage your own files only, commit ...
git merge origin/main          # to update; never force-push
git diff origin/main...HEAD --stat
git push -u origin HEAD
gh pr create --title "<type>(<area>): <English title>" --body-file <file>   # fill in the PR template's sections
```

- Branch types: `feat`, `fix`, `docs`, `test`, `perf`, `chore`.
- `gh pr create --body-file` skips `.github/pull_request_template.md`; copy its sections into the body yourself.
- **Merging**: after the PR's local verification passes, `scripts/hooks/merge-pr.sh <number>`, not `gh pr merge`
  directly. It scans the PR's changes, commit messages, title and body with this machine's private values, then
  squash-merges exactly the head it scanned and deletes the branch.
- After merging, remove your worktree by its literal path (`git worktree remove .worktrees/<branch>`) and make sure
  the issue is closed.

## Checking PRs with no linked issue

`.github/workflows/pr-needs-issue.yml` runs when an operator dispatches it with `pr_number=<number>`. It accepts
`fix(es|ed)`, `close(s|d)`, `resolve(s|d)` or `ref(s)` followed by `#number`, or a link to an issue in this
repository, outside code blocks and comments. Without one it comments and closes the PR, and reopens it once a link
is added. Tests: `node scripts/test/pr_needs_issue_test.mjs`; after changing the workflow also run `actionlint`.
