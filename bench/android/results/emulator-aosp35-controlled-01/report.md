# Android benchmark report

**EMULATOR RESULTS — not device results.** Software virtualization and graphics are not representative of hardware performance.

Lower-is-better regression limits: more than 5% AND more than 0.1 ms. All raw AndroidX files are retained.

| Benchmark | Metric | Reference p50 | Generated p50 | Δ | Reference p99 | Generated p99 | Δ | Samples |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| rowRecomposition | allocationCount | 748.000 native | 677.000 native | +0.00% | 825.000 native | 835.000 native | +0.00% | 5 / 5 |
| rowRecomposition | timeMs | 124.681 ms | 120.964 ms | -2.98% | 251.360 ms | 327.377 ms | +30.24% | 50 / 50 |

**Result: FAIL**
