# Roadmap

Phases and the workstreams inside them. Each workstream is a GitHub issue; this page lists them so people and Agents
can pick one. Update it when a phase ends or a workstream is added.

## Phase 0: foundations

The generator skeleton, the subset contract and the repository's tooling, so every later workstream has a place to
land and a way to test.

## Phase 1: the first vertical slice

A settings-style screen (sections, rows, toggles, text fields, buttons, a list) written once in Swift, generated for
Android and HarmonyOS, compiled in the examples, compared with a hand-written reference on performance, and mixed
with hand-written native code in both directions.

**Exit**: the slice builds on all three platforms; paired screenshots match; benchmarks show no regression against the
hand-written reference; an existing hand-written screen in an example app is replaced by its generated version and
back again.

## Phase 2: breadth

More views and modifiers, navigation, lists at scale, animations through per-platform variation, build plugins
(SwiftPM, Gradle, hvigor), and adoption in a real app.

## Workstreams

The list of issues for the current phase is kept in the issue tracker; search for open issues with
`label:enhancement` and read each issue's `Depends on` line before picking one.
