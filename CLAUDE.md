# CLAUDE.md

Refract: write a screen once in a subset of SwiftUI; Refract generates native Jetpack Compose (Android) and ArkUI
(HarmonyOS) source at build time, while iOS compiles the same file as ordinary SwiftUI. No runtime, no performance
regression, incremental adoption, and free mixing with hand-written native code.

## Highest-priority rules

Read [the super rules](docs/SUPER_RULES.md) and [the goals](docs/GOALS.md) before acting. They take precedence over
this file, `AGENTS.md` and all other repository documentation. Changing either file needs a GitHub issue and explicit
approval from administrator `chyroc` in that issue first; no Agent or delegated task may bypass this, even to fix a
failing check.

Every PR states which of the five goals it touches and the evidence that each still holds.

## Conventions (mandatory)

### Workflow

- **Every change goes issue → claim → branch → PR → merge after local verification passes** (`docs/collaboration.md`).
  Code, docs and config alike; never commit or push to `main` directly.
- **Several Agents work here at once**: work in your own worktree from `origin/main`
  (`git worktree add .worktrees/<branch> -b <branch> origin/main`), stage only your own files (never `git add .` or
  `-A`), and check that `git diff origin/main...HEAD --stat` lists only them before pushing. Bring a branch up to date by
  merging `origin/main` (preferred over a rebase); never force-push.
- **Small PRs**: one issue, one PR, reviewable in one sitting. Split large work into a sequence of issues.
- **Write lessons down as you go**: pitfalls into `docs/lessons/<topic>.md` (index `docs/lessons/README.md`), design
  trade-offs into the relevant doc. New maintained docs go into the Docs index below.

### Public repository

This is a public open-source repository, and its history is public too.

- **Write as if anyone can read it**: code, docs, comments, fixtures, file names, commit messages, issue and PR text.
- **No private information**: no internal company names, internal services or repositories, intranet domains, IPs,
  host names, real people's names, personal accounts or email addresses, tokens or keys. Examples use placeholders
  (`<host>`, `me@example.com`). `scripts/privacy_check.py` checks; `git config core.hooksPath scripts/hooks` runs it
  on commit and push, and `scripts/hooks/merge-pr.sh` runs it before merging.
- **No attribution trailers** naming a model, a model provider or an AI tool in commit messages or PR bodies.
- Values specific to your machines go in `CLAUDE.local.md` (not committed).

### Language

- **English for everything people read in the repository**: code comments, docs, commits, PR titles and bodies (a
  squash merge makes them the commit on `main`), issues and comments. `README.md` and `README.zh-CN.md` carry the same
  content and change in the same PR.

### Engineering

- **Goals first** (`docs/GOALS.md`): no runtime library, no measured regression, compile-time only, adoptable one
  screen at a time, mixable with native code. If a design needs to bend a goal, stop and open an issue.
- **Generated code is product code**: idiomatic, formatted, deterministic, with a "generated, do not edit" header.
  Every generator change updates golden fixtures; read the diff of the generated output before committing.
- **Diagnostics over fallbacks**: unsupported input is a build-time error that names the construct, says why and
  suggests an alternative. Never emit approximate code silently.
- **Performance rules live in the generator**, documented in `docs/performance.md`; a rule added there comes with a
  fixture that shows the generated pattern.
- **Swift 6 strict concurrency** for the generator; it builds and tests on macOS and Linux.

## Build and verify

- Generator: `swift build` and `swift test` at the repository root.
- Fixtures: the golden test target regenerates every `Fixtures/` case and fails on any difference.
- Examples: each example's README says how to build it and which generated files it compiles.
- Workflows: `actionlint` for any change under `.github/workflows/`; `node scripts/test/pr_needs_issue_test.mjs` for
  `pr-needs-issue.yml`.
- Every change: `python3 scripts/privacy_check.py`.
- Say in the PR what you ran and what you could not run (a missing toolchain, no device). Never present simulator or
  emulator numbers as device results.

## Layout

| Path | Contents |
| --- | --- |
| `Package.swift`, `Sources/`, `Tests/` | The generator and its tests (SwiftPM) |
| `Fixtures/` | Golden conformance corpus: Swift input, expected Kotlin and ArkTS, expected diagnostics |
| `examples/` | Apps mixing generated and hand-written code |
| `bench/` | Performance comparisons, generated vs hand-written |
| `docs/` | Design docs (index below) |
| `scripts/` | Hooks, privacy scan, repository checks |

## Docs index

| Area | Docs |
| --- | --- |
| Rules and goals | `docs/SUPER_RULES.md` highest-priority rules · `docs/GOALS.md` the five goals and their evidence |
| Design | `docs/architecture.md` pipeline, modules, models, mixing, testing, open decisions · `docs/arkui-backend.md` ArkTS lowering, list identity and toolchain verification · `docs/compose-backend.md` Kotlin lowering, list identity, performance rules · `docs/compose-examples/` hand-written Swift/Kotlin design examples; the README and per-case Notes explain each lowering decision · `docs/state-and-models.md` state, bindings and observation · `docs/interop.md` native components, platform variation and generated entry points · `docs/navigation.md` typed destinations, native hosts, back/lifecycle and verification limits · `docs/remote-images.md` bounded native remote-image sources and lifecycle · `docs/document-preview.md` typed document preview ownership and synthetic verification · `docs/forms.md` typed form validation, submission and retry · `docs/markdown.md` bounded typed rich text, native links, code blocks and verification limits · `docs/localization.md` native string resources, typed formatting and diagnostics · `docs/accessibility.md` localized native semantics, actions, traversal and verification limits · `docs/mapping.md` design-system mapping and validation · `docs/subset.md` accepted SwiftUI subset and diagnostics · `docs/selection-and-dragdrop.md` bounded text selection, typed drag/drop payload contract and cancellation rules · `docs/selection-link-context.md` bounded literal selection ranges, link activation and model-owned context snapshots · `docs/message-projection.md` bounded application-owned message snapshots and native identity | · `docs/performance.md` generated-code performance rules and benchmark evidence
| Adoption | `docs/adoption.md` adopt one screen and switch back · `docs/swiftpm-integration.md` bounded build-time consumer generation, explicit inputs/outputs and sandbox limits · `docs/generation-configurations.md` explicit debug/internal/release output roots, version pinning and publication · `docs/production-readiness.md` evidence levels, production gates, verification owners and supported adoption boundaries · `examples/` mixed native apps |
| Process | `docs/collaboration.md` claims, comment templates, PRs, merging · `docs/roadmap.md` phases and workstreams · `docs/ci.md` repository checks, CI prerequisites and local verification · `docs/cli.md` output transactions, exit statuses and mapping compatibility · `docs/harmony-toolchain.md` authorized SDK prerequisites and the explicit native-compile blocker · `docs/packaging.md` local CLI artifacts and executable discovery |
| Lessons | `docs/lessons/` pitfalls by topic; every file under this directory is listed in its README |
