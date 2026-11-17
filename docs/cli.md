# CLI: generation safety and compatibility

`refract generate` validates every supplied input, its mapping and resource catalogs, and generates both platform
sources in memory before publishing any file. `refract check` uses the same in-memory generation, but only compares
committed files; it never calls the output writer. See `docs/mapping.md` for the input contract and `docs/adoption.md`
for the build integration.

`refract --version` prints the CLI version and `RefractVersion.sourceRevision`. The packaging script stamps the
complete commit into its clean archive; public source archives expand that same identity through `export-subst`.
Neither build invokes Git or infers a moving branch. The version command writes no output files, does not change
generation and is not a supported-release or readiness claim.

## Publishing and concurrent invocations

A generate invocation publishes only the Kotlin and ArkTS files derived from its supplied inputs. It does not remove
unrelated or no-longer-generated screens; review and remove obsolete generated files explicitly. Input base filenames
must be unique, and two outputs resolving to the same path are rejected before publication.

Each output directory has a `.refract-generate.lock` directory. Aliases of the same resolved output directory share a
lock. Refract serializes publication within all affected directories, acquiring locks in deterministic path order, and
waits up to 30 seconds. A busy lock is a nonzero,
actionable failure, not an interleaved write. After a process crash, confirm no generator is running before removing a
stale lock. External editors and non-Refract writers do not participate in this exclusion and must not write generated
files concurrently.

New contents are staged next to their destination. Each individual file is replaced atomically with a same-filesystem
POSIX rename. Existing files are backed up until every replacement succeeds. An ordinary staging or replacement failure
restores replaced files, removes newly created files and temporary files, and leaves unrelated files untouched. Only
regular files or absent destinations are replaceable: a directory, symbolic link or special file is rejected without
following or deleting it. If rollback itself fails, the diagnostic identifies the affected paths and says that manual
inspection is required.

A multi-file or cross-platform batch is **not one atomic filesystem transaction**. Readers that need an entirely
consistent set must wait for the command to finish or coordinate through the same output directories. Successful
replacement followed by a cleanup failure exits nonzero and explicitly says the new outputs are already published.
Forced termination, power loss and filesystem corruption cannot run rollback; remove leftover `.refract-temporary-*`
or `.refract-backup-*` files only after checking that no generator is running and reviewing the committed files.
No hidden user files are automatically removed during recovery.

## Exit behavior

The public command contract retains status `0` for success and `1` for every failure. Invalid options, unreadable
input, mapping/schema errors, unsupported source constructs, stale checked output, lock timeouts and output I/O
failures all exit `1` with a diagnostic on stderr. No output-write failure is reported as successful generation.
Diagnostics name the file or option where available and suggest the supported correction. There is no partial-success
exit status: either every requested output is published, the previous set is restored, or the error explicitly says
that new output was published or manual recovery is needed.

## Mapping and breaking-change policy

`schemaVersion: 1` is the full mapping format and `Sources/RefractMapping/Resources/refract.schema.json` is its
normative schema. The previously published native-component-only draft with `version: 1` remains a separate supported
input. It is normalized explicitly by the loader; it is not an alias for a partial full mapping and must not silently
gain defaults for unrelated registries. CLI end-to-end tests generate both native targets from that legacy format.

Within a supported schema version, unknown keys, malformed values, unsupported versions and incompatible platform
interfaces are errors, never ignored extensions or best-effort native calls. Additive mapping fields need coordinated
schema, loader, diagnostics and fixture coverage. A future incompatible schema requires a new explicit version and a
migration/diagnostic path; changing the meaning of an existing version is not a compatible release. Generated native
API signatures may change only with the typed Swift/mapping contract and review of the generated diff, not as a silent
side effect of failure-safety changes. This work does not introduce a schema version bump or change generated source
contents.

## Evidence and limits

`Tests/RefractCLITests/GeneratedOutputWriterTests.swift` injects failure between replacements and covers restoration,
new-file rollback, directory and symbolic-link preservation, stale locks, path collisions and concurrent writers.
The CLI tests exercise real processes, concurrent invocations, unreadable inputs, schema diagnostics and the legacy
mapping. `Tests/RefractCLITests/CheckModeTests.swift` covers the independent read-only checker. These are host
filesystem tests, not device performance evidence; no generated-code shape or runtime dependency is changed.
