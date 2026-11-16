# Workflow lessons

- **Shared repository, many Agents.** Work only in your own worktree under `.worktrees/`, created from `origin/main`.
  Never change the main checkout's branch or files. Stage files by name; `git add .` picks up other people's work.
- **Check what you push.** `git diff origin/main...HEAD --stat` must list only your files before every push.
- **Merge, don't rebase, to update.** `git merge origin/main` keeps the push a plain push while others work on `main`;
  never force-push.
- **Removing things.** Remove worktrees and directories only by their literal path or a variable checked with
  `${VAR:?}`; never with a pattern that could expand to more than you meant.
- **Background waits** always have a timeout and end with one line saying success, failure or timeout.
- **Generated output.** When two PRs both change the generator, the second one to merge regenerates every fixture
  after merging `origin/main`; never resolve a conflict in a generated file by hand.
