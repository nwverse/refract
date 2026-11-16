# switch-enum

A Swift `enum` with `String` raw value but no associated values becomes a Kotlin `enum class`. The `when` is
exhaustive: no `else` branch is needed because the compiler checks coverage. A non-exhaustive Swift `switch` (one
that would need `default:`) is rejected at the frontend with `RF-C005`.

Cases are emitted in declaration order so the diff of adding a case is a single line in both files.
