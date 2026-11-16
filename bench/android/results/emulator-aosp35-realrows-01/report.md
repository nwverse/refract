# Android benchmark report

**EMULATOR RESULTS — not device results.** Software virtualization and graphics are not representative of hardware performance.

Lower-is-better regression limits: more than 5% AND more than 0.1 ms. All raw AndroidX files are retained.

| Benchmark | Metric | Reference p50 | Generated p50 | Δ | Reference p99 | Generated p99 | Δ | Samples |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| rowRecomposition | allocationCount | 783.000 native | 798.000 native | +0.00% | 978.000 native | 1044.000 native | +0.00% | 5 / 5 |
| rowRecomposition | timeMs | 149.006 ms | 100.541 ms | -32.53% | 615.354 ms | 170.044 ms | -72.37% | 50 / 50 |

**Result: PASS**
