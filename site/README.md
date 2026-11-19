# Component gallery

A static, dependency-free site that shows which SwiftUI constructs Refract supports, how each one looks on iOS,
Android and HarmonyOS, the exact Kotlin and ArkTS the generator must produce, the diagnostics for rejected forms, and
how to adopt Refract in an existing app.

```sh
node site/serve.mjs                      # builds site/dist, then serves http://127.0.0.1:4310
PORT=8080 HOST=0.0.0.0 node site/serve.mjs
node site/build.mjs                      # build only
```

Requires Node.js 18 or newer. No packages are installed and nothing here is part of the generator or of any
generated application.

## Where the content comes from

| Content | Source |
| --- | --- |
| Code panels, fixture browser, diagnostics | Every case listed in `Fixtures/Corpus.json`, read verbatim at build time |
| Mapping reference | The SwiftUI/Compose/ArkUI tables in `docs/subset.md` |
| Component catalog and previews | `site/src/catalog.js` (hand-written; each entry links real fixtures) |

The three device previews are HTML drawings styled after each toolkit (SwiftUI, Material 3, ArkUI). They are labeled
as illustrative on every page and are never presented as screenshots. When a backend's lowering changes, update the
entry's one-line Compose/ArkUI summary and preview so they still match the golden output.

## Files

- `build.mjs` collects fixtures and subset tables into `dist/data.js` and copies `src/`.
- `serve.mjs` rebuilds and serves `dist/` for local preview.
- `src/app.js` routing and pages; `src/catalog.js` entries; `src/preview.js` and `src/devices.css` device drawings;
  `src/highlight.js` a small syntax highlighter.
