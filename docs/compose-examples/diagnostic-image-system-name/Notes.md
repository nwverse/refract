# diagnostic-image-system-name

SF Symbols are an Apple-only asset. There is no faithful Compose translation, so the emitter fails the build with
`RF-C002` instead of silently dropping the image or substituting a placeholder (goal 3).

The suggested alternatives are a drawable resource (`Image("star", bundle:)` → `painterResource(R.drawable.star)`)
or a native component declared in `refract.json` (#7).
