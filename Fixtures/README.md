# Golden fixtures

Each directory is one conformance case. `Input.swift` is required; `refract.json` is optional. A valid case has
`Expected.kt` and `Expected.ets`. A rejected case has `Expected.diagnostics` and no generated-output files.
Diagnostics use the stable format `file:line:column: error [code]: message Suggestion: alternative`, one per line.

The runner discovers directories in lexical order and regenerates every case. The test fails on any byte difference.

Run all fixtures from the package root:

```sh
swift test --filter GoldenTests
```

For one case, filter its directory name:

```sh
swift test --filter 'GoldenTests.*hello'
```

To review or update expectations after an intentional generator change, generate into a temporary directory and
compare it with the checked-in files:

```sh
swift run refract generate --input Fixtures/hello/Input.swift --mapping Fixtures/hello/refract.json \
  --android-out /tmp/refract-golden/android --harmony-out /tmp/refract-golden/harmony
diff -u Fixtures/hello/Expected.kt /tmp/refract-golden/android/Input.kt
diff -u Fixtures/hello/Expected.ets /tmp/refract-golden/harmony/Input.ets
```

Copy the reviewed output into `Expected.kt` and `Expected.ets`, then run the complete golden suite. Never update an
expectation just to hide a diagnostic or an unintended output change.

## Extension contract

The first IR is a typed, `Sendable`, `Codable` value tree. Backends own their emitters; feature work should add
supporting declarations in separate source files and preserve existing diagnostic codes and golden behavior.
