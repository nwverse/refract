# The benchmark screen uses no reflection. Keep its ordinary native entry point for R8.
-keep class dev.refract.bench.BenchmarkActivity { <init>(...); }
