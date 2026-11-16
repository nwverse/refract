# Repository checks and CI

This page describes the checks owned by `ci.yml`, how to run them locally, and the remaining bootstrap dependencies.
The checks add no application dependency, generated-code runtime or host-application setup.

## Local checks

Run these commands from a repository checkout:

```sh
python3 scripts/privacy_check.py
python3 -I scripts/test/test_privacy_check.py
python3 -I scripts/test/test_doc_paths.py --self-test
python3 -I scripts/test/test_doc_paths.py
node scripts/test/pr_needs_issue_test.mjs
actionlint
```

The privacy tests copy the scanner into temporary git repositories and replace its home, configuration and git
configuration with fixture values. They exercise tracked, staged, range, commit-message and squash-message scans;
positive and negative samples; redacted path diagnostics; binary files; symlinks; and unrelated histories. They do
not read the developer's private word list. The ordinary privacy command remains a separate required check because
it scans the real checkout with the machine's private values.

The documentation checker verifies that every Markdown file under `docs/` is covered by the Docs index in
`CLAUDE.md`, including files under an indexed directory such as `docs/lessons/`. It resolves relative Markdown links
and images, rejects links that leave the repository, and checks literal repository paths in inline code. Fenced
examples, command arguments and explicit placeholders are not paths. It does not validate external URLs or heading
anchors, which would require network access and a Markdown parser.

Install actionlint separately when changing `.github/workflows/`. CI downloads the pinned release only when a
workflow changes, validates the archive against the SHA-256 published in that release's checksums file, and invokes
the binary from an empty temporary directory.

## CI jobs

The workflow runs on pull requests, pushes to `main`, and manual dispatch. It has read-only repository permissions
and never interpolates pull-request text into a shell command. Repository checks and changed-workflow linting are
independent jobs.

During the initial repository bootstrap, the full documentation check waits for the following paths promised by
their owning workstreams:

| Prerequisite | Owner |
| --- | --- |
| `docs/subset.md` | #2 |
| `docs/performance.md` | #9 |
| `docs/adoption.md` | #10 |

The workflow prints an annotation while any prerequisite is absent. This is not a permanent allowlist: the checker
itself has no missing-path exceptions, and the full command must run in CI before #11 closes. If a promised path is
renamed, update its original documentation references in the owning change rather than deleting a broken reference.

Both Swift jobs run `swift build`, the complete `swift test`, and the documented `swift test --filter GoldenTests`
regenerate-and-diff check. They then require no fixture diff and no unexpected generated or dependency files. The
jobs use Swift 6.0.3, the language-mode baseline declared by `Package.swift`, on Ubuntu 24.04 and macOS 15; the local
Linux verification uses Swift 6.4.2. Dependencies stay locked by `Package.resolved`. There is no skip for the Swift
or fixture jobs. macOS CI verifies generator portability; it does not constitute an iOS device or simulator
measurement.

## Branch integration

Other changes must merge the latest `origin/main` before local verification. The main CI workflow does not use
third-party mutable action tags, does not request write access, and does not check out code for the separately
maintained, manual issue-link enforcement workflow.
