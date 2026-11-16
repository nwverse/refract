# Contributing to Refract

Thanks for helping. This page is the starting point for people. The complete rulebook, which people and Agents follow
alike, is [`CLAUDE.md`](CLAUDE.md); [`docs/SUPER_RULES.md`](docs/SUPER_RULES.md) and [`docs/GOALS.md`](docs/GOALS.md)
take precedence over everything else.

## Getting set up

- Swift 6.2 or later (Xcode on macOS, or a Swift toolchain on Linux): `swift build && swift test`.
- For the Android examples: JDK 17+ and the Android SDK. For the HarmonyOS examples: the HarmonyOS command-line tools.
- `git config core.hooksPath scripts/hooks` runs the privacy scan on every commit and push.

## How a change gets in

Every change, code, docs or config, goes **issue → claim → branch → PR → merge after local verification passes**.
Details and copyable commands: [`docs/collaboration.md`](docs/collaboration.md).

1. **Look for duplicates** in open and closed issues and PRs.
2. **Find or open an issue** that says what and why (`bug`, `enhancement` or `documentation`).
3. **Claim it** with a comment starting `Claim:`, then `Plan:` and `ETA:`; add `Acceptance:` naming the goals the work
   touches and the evidence for each.
4. **Work on your own branch** named with the issue number (`feat/12-short-name`). Update it by merging `origin/main`;
   never force-push.
5. **Open one PR per issue**, in English, with `Fixes #N` (or `Refs #N`), and fill in the
   [PR template](.github/pull_request_template.md), including the goals self-check.
6. **Merge after local verification passes**, with `scripts/hooks/merge-pr.sh <number>` if you have write access.

## Rules that catch most first PRs

- **Never hand-edit generated files**; change the generator and regenerate the fixtures.
- **No performance regression and no runtime library**, ever ([`docs/GOALS.md`](docs/GOALS.md), goal 2).
- **Unsupported input gets a diagnostic**, not approximate output.
- **This repository is public**, and so is its history: no private information or internal names anywhere.
- **English** for everything in the repository; `README.md` and `README.zh-CN.md` change together.

## Working with an AI Agent

Agents are welcome and follow the same rules. Point yours at [`CLAUDE.md`](CLAUDE.md). The person whose GitHub account
posts the claim and the PR is responsible for the Agent's work. Commit messages and PR bodies carry no attribution
trailers naming a model or tool.
