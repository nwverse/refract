# Typed external links and deep-link handoff

This contract lets a screen request a bounded external link or app deep link without giving generated code a router,
an intent dispatcher or permission to open a URL. It extends the existing `RefractNativeView` boundary; it is not a
second view type or a runtime service.

## Source contract

A handoff component has exactly three cross-platform inputs, in this order:

```swift
struct NativeHelpLink: RefractNativeView {
    let destination: RefractLinkDestination
    let policy: RefractLinkPolicy
    let handoff: RefractLinkHandoff
    @State private var isConfirming: Bool = false

    var body: some View { /* The application's ordinary SwiftUI confirmation UI. */ }
}
```

`destination` uses one of these closed constructors, with literal fields only:

```swift
RefractLinkDestination.https(host: "docs.example.test", path: "/help/start")
RefractLinkDestination.deepLink(scheme: "app+test", host: "router.example.test", path: "/article/42")
```

`https` fixes the kind to `external` and its scheme to HTTPS. `deepLink` requires an explicit lowercase custom
scheme. The path is static data, not a URL template. No raw URL string, interpolation, model-produced URL,
percent-decoding, query or fragment is accepted. The initial path grammar is `/` or absolute ASCII segments made of
unreserved characters, with no empty, `.` or `..` segment and no trailing slash. Hosts are exact lowercase DNS names
with at least two labels: no wildcard, suffix match, IP literal, port, user information or credentials. The final
label must not consist only of decimal digits or be `0x` followed only by hexadecimal digits (including none).
This bounded syntax rejects the number-ending host forms that platform URL parsers reserve for IPv4, including
shortened, octal, hexadecimal and mixed-radix spellings, without interpreting or normalizing the host. A scheme is
at most 32 lowercase ASCII characters; `http`, `file`, `content`, `intent`, `javascript` and `data` are always
rejected. These are deliberately bounded source rules, not a claim that a URL parser makes an arbitrary destination
safe.

The policy is a nonempty list of at most 16 exact `(scheme, host)` pairs, with no duplicates:

```swift
RefractLinkPolicy(allowed: [
    (scheme: "https", host: "docs.example.test"),
    (scheme: "app+test", host: "router.example.test")
])
```

The frontend rejects a destination outside that policy before either backend writes output. `RFLINK001` covers an
unsupported constructor, declaration or handoff shape; `RFLINK002` covers invalid values and allowlist mismatches.
No dynamic destination is silently converted into a string argument or accepted as an arbitrary native object.

The app-owned source-only `RefractLinkDestination`, `RefractLinkPolicy`, `RefractLinkHandoff` and
`RefractLinkHandoffResult` declarations are ordinary Swift types, not a linked Refract library. The handoff protocol
has `begin(_:completion:)` and `cancel(_:)`. Outcomes are `handedOff`, `cancelled`, `disallowed`,
`unsupportedScheme` and `unavailable`. A native confirmation cancel action reports `cancelled` through its local
result state without calling `begin` or `cancel` on an unstarted request. `cancel` is for an already-started pending
request whose owner is being disposed. A completion must be idempotent: once cancelled or disposed, a late
completion cannot open another destination or replace the current request's result. The private `isConfirming`
state in this native component is iOS implementation state, not a fourth cross-platform parameter.

## Generated and native responsibilities

The generated Kotlin and ArkTS construct immutable `LinkDestination`/`LinkPolicy` values and pass them, plus the
injected native `LinkHandoff`, to the mapped app component. Native target types are `LinkDestination`, `LinkPolicy`,
`LinkAllowlistEntry` and `LinkHandoff`; there is no generated singleton, service locator, global URL registry,
platform dispatcher, arbitrary target-source template or URL-opening API. Mapping declarations only bind these
typed values to an app-owned component.

A conforming native implementation:

- shows the destination's scheme, host and path in native confirmation UI before calling `begin`;
- checks its bounded scheme/host/path rules and exact allowlist both before showing confirmation and again when the
  user confirms, because the app's policy may have changed while the dialog was visible;
- delivers a cancellation outcome when confirmation is dismissed, and never calls `begin` for that dismissed link;
- calls the app-owned `cancel` when a pending handoff leaves composition/page ownership, and ignores late
  completions for that cancelled request. The effect keyed by the pending destination is the request's owner;
  a changed destination/handoff cancels the captured old request and returns to idle. Each request records a terminal
  finished state on completion or cancellation, so parameter-change cancellation and subsequent disposal cannot
  double-cancel it. Completion checks that request-local terminal flag, not a possibly unsynchronized derived state.
  Disposal reads the current pending request, never a stale closure capture. Clearing pending on normal
  completion must not report a cancellation. Waiting for actual native idle/disposal, not
  clearing it on normal completion must not report a cancellation. Waiting for actual native idle/disposal, not
  just the state-write callback, is necessary when testing this behavior;
- delegates the actual deep-link route or external handling to the application's existing router/lifecycle. It does
  not create an Android `Intent`, call `startActivity`, register an intent filter, call iOS `openURL`, or construct
  an ArkUI router operation in generated code.

The app remains responsible for authorization, authentication, any broader destination policy, platform capability
checks, final routing and an unavailable-handler result. The generator's allowlist is a source-level guard, not an
operating-system security boundary. An app must validate any values received from outside this closed source
contract before converting them to this typed native representation.

### Coordination with rich text

Issue #201 owns rich-text ranges, selection, link activation and AI-edit callbacks. Its `RefractLink` label and UTF-16
range are not this destination value, and this issue does not duplicate those callbacks or markup rules. A native
#201 activation can pass an already validated destination to an app-owned implementation of this handoff; no
selection or Markdown string is implicitly opened. Integrating those two separate contracts is application code,
not a runtime adapter or a second link-opening path in #201.

## Verification and limits

`Fixtures/interop-link-handoff/` contains both external and deep-link source and the exact dual-backend generated
outputs. `interop-link-handoff-reject/` and frontend parameterized tests cover unsupported schemes, wildcard or
credential-bearing hosts, ports, path traversal, queries/fragments, arbitrary strings, dynamic policy, duplicate
entries and a missing injected handoff. The Android fixture compile manifest includes the accepted case.

`examples/android/fixtures/src/native/java/example/app/LinkHandoff.kt` is the app-owned native component. Native
JVM Compose tests invoke the actual CLI-generated `HelpLinkScreen` with a controlled fake handoff and synthetic
`example.test` hostnames. They cover confirmation, cancellation, scheme/host rejection, policy change before
confirmation, disposal and stale completions. They do not contact a network, open a URL, run an emulator/device,
or establish performance parity. ArkTS and iOS source are source/golden evidence only on this Linux machine: no
HarmonyOS compiler, Xcode or simulator was used for this slice. Actual iOS and HarmonyOS confirmation, cancellation
and lifecycle behavior require their native toolchains and application-owned implementations.
