# Forms: typed validation and submission

This is the bounded form contract. It covers required fields, one cross-field equality rule, a draft that
survives rejected attempts, model-owned pending/error state and retry. Business validation, networking and error
wording stay in the app's model implementation (`docs/GOALS.md` non-goal "business logic translation"). The
generator type-checks declarations and lowers them to native state and comparisons; it never executes Swift
validation bodies and never hides a rule inside a target template.

## Source contract

```swift
protocol SignupModel: RefractModel {
    var submitting: Bool { get }
    @refractText var submissionError: String { get }
    @refractAsync func submit(email: String, password: String, confirmation: String)
    @refractAsync func retry(email: String, password: String, confirmation: String)
}

struct SignupScreen: View {
    let model: SignupModel
    @State private var form = refractForm {
        Field("email", initial: "", rules: .nonEmpty)
        Field("password", initial: "", rules: [.nonEmpty, .equals("confirmation")])
        Field("confirmation", initial: "")
    }

    var body: some View {
        Form {
            TextField("settings.email", text: $form.email)
            if model.submitting { Text(verbatim: "Submitting…") }
            if refractPresent(model.submissionError) { Text(model.submissionError) }
            Button("settings.submit") { form.submit(model.submit) }
                .disabled(model.submitting)
            if refractPresent(model.submissionError) {
                Button("settings.retry") { form.submit(model.retry) }
                    .disabled(model.submitting)
            }
        } (form: $form)
    }
}
```

- **`refractForm { Field(...) }`** declares String fields, a literal initial value and the bounded rule vocabulary
  `.nonEmpty` and `.equals("siblingField")`. Field names are Swift identifiers, unique within the view and not
  colliding with other states or models. `@State private var form = refractForm { ... }` owns the draft locally;
  `@Binding var form: RefractForm = refractForm { ... }` receives the same declaration from a parent. There is no
  runtime form object: the declaration is compile-time-only metadata, lowered to one native value per field.
- **`Form { ... } (form: $form)`** groups the screen without changing the native view tree; it lowers to the same
  container as `VStack`. `$form.email` is the field's writable binding, and `form.email` is its read.
- **`form.submit(model.action)`** is the only new statement shape, allowed as a button's single action. The action
  must be declared `@refractAsync` on the model, and every action parameter must match a form field's name and type
  in declaration order. That is the complete mapping: no closures, no transformations, no argument reordering.
- **Pending and duplicate-submit prevention are the model's own observable state.** `.disabled(model.submitting)`
  lowers to the native enabled flag, so a second tap while an attempt is running never reaches the model. Refract
  does not synthesize a second pending flag, and the generated code never starts a task.
- **`@refractText`** declares a get-only String property whose native value may be absent, such as an error
  message. It lowers to `State<String?>` in Kotlin and `string | null | undefined` in ArkTS. `refractPresent(...)`
  is the only way to test it in a condition, and lowers to a native null check. Reading it as `Text` supplies
  Kotlin's required non-null argument through `?: ""`; no error copy is generated.
- **`@refractAsync`** declares a synchronous requirement that starts or refuses one native attempt and returns
  whether it was accepted (`Boolean` / `boolean`). The implementation owns its coroutine or task, its pending flag
  and its result; Swift's real `async` and `throws` remain rejected.

The iOS app declares the compile-time-only support types so the same file is ordinary SwiftUI: the
`@refractText`/`@refractAsync` attribute macros (or attribute declarations), the `refractForm`/`Field` builders and
`RefractForm`, and `refractPresent`. None of them ships in the generated Kotlin or ArkTS.

## Lowering

Compose:

```kotlin
var formEmail by remember { mutableStateOf("") }
Button(
    onClick = {
        if (formEmail.isNotEmpty() && formPassword.isNotEmpty() && formPassword == formConfirmation) {
            model.submit(email = formEmail, password = formPassword, confirmation = formConfirmation)
        }
    },
    enabled = !(model.submitting.value),
) { ... }
```

ArkUI:

```typescript
@Local private formEmail: string = '';
Button()
  .onClick(() => {
    if (this.formEmail.length > 0 && this.formPassword.length > 0 && this.formPassword === this.formConfirmation) {
      this.model.submit(this.formEmail, this.formPassword, this.formConfirmation);
    }
  })
  .enabled(!(this.model.submitting))
```

The guard is the declared rules and nothing else. Invalid input never reaches the model; a valid submission is a
direct model call. Retry is the same construct with a second action, so the preserved draft is reused rather than
reset. `docs/state-and-models.md` owns the observation rules these reads follow.

## Diagnostics

| Code | Rejected construct | Alternative |
| --- | --- | --- |
| `RFFORM001` | Malformed form/field declaration, duplicate field, or a field name colliding with another property | Use `refractForm { Field("name", initial: "") }` with unique identifiers |
| `RFFORM002` | Rule outside `.nonEmpty` / `.equals("field")`, or a read of an undeclared field | Declare only presence and equality here; keep business rules in the model |
| `RFFORM003` | `.equals` names a missing or differently typed sibling | Compare two declared String fields of the same form |
| `RFFORM004` | `form.submit` references a non-async action, an undeclared action, or parameters the form cannot supply | Declare `@refractAsync` with parameters matching the form fields |
| `RFFORM005` | `$form` used directly as a control binding | Project one field, for example `$form.email` |
| `RFFORM006` | `refractPresent` applied to a property without `@refractText` | Declare the optional text with `@refractText` |
| `RFFORM007` | `.disabled` applied to anything other than a declared Bool model property | Use `.disabled(model.submitting)` |

Anything beyond this slice — length and format rules, asynchronous validators, non-String fields, optional binding
over the error text, cross-form comparisons, computed conditions — is rejected at build time, not approximated.
Those rules belong in the app's model, exposed as typed properties and actions.

## Evidence and limits

- `Fixtures/form-validation/` is the accepted dual-backend golden; the `form-reject-*` cases pin the diagnostics.
- `examples/android/fixtures/src/test/java/com/example/refract/form/GeneratedSignupFormTest.kt` runs the staged,
  CLI-generated `SignupScreen` on Native JVM Compose (Robolectric). It proves empty-draft rejection, cross-field
  rejection with the draft preserved, duplicate-submit prevention while pending, model-driven error display and
  retry with the same draft, and draft preservation across model-driven recompositions. This is a Native JVM
  result, not an emulator or device measurement, and it makes no performance claim.
- The fixture Kotlin compiles with the real Android toolchain through the fixture manifest. ArkTS output is golden
  and source-reviewed only: the HarmonyOS toolchain is not available here, so compiler acceptance and `@Local`
  observation are not verified on HarmonyOS. iOS compilation is not verified on macOS.
