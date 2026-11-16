package dev.refract.bench.test

import androidx.activity.ComponentActivity

/** Hosts test-owned composables only; neither benchmark variant runs in this activity. */
class MicrobenchmarkActivity : ComponentActivity()
