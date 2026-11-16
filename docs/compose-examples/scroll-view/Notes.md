# scroll-view

`ScrollView { VStack { … } }` collapses to a single `Column` with `verticalScroll(rememberScrollState())`: there
is no need for a nested `Column` inside another `Column`. The `VStack`'s `spacing` becomes the outer column's
`verticalArrangement` so no information is lost.

The scroll state is `rememberScrollState()` (not `remember { ScrollState(0) }`) so it participates in Compose's
state saving across configuration changes for free.
