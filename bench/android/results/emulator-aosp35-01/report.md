# Android benchmark report

**EMULATOR RESULTS — not device results.** Software virtualization and graphics are not representative of hardware performance.

Lower-is-better regression limits: more than 5% AND more than 0.1 ms. All raw AndroidX files are retained.

| Benchmark | Metric | Reference p50 | Generated p50 | Δ | Reference p99 | Generated p99 | Δ | Samples |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| rowRecomposition | allocationCount | 856.000 native | 744.000 native | +0.00% | 988.000 native | 908.000 native | +0.00% | 5 / 5 |
| rowRecomposition | timeMs | 144.410 ms | 309.204 ms | +114.12% | 350.890 ms | 905.606 ms | +158.09% | 50 / 50 |

**Result: FAIL**
