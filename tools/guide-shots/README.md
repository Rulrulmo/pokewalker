# guide-shots

The public site's 육성 가이드 pictures (`docs/guide/img/`, captions in `docs/guide/README.md`) come from the app's own renders. Nothing here is built
into the app: `build.sh` compiles `Sources` and `Tests`, and `Package.swift` excludes `tools`.

To make them again (after a UI change):

1. Copy the repository somewhere else, without `.git`. `build.sh` must sit next to the app, or `--shots` refuses to run.
2. In the copy, put `GuideShots.swift` into `Tests/`. Make `shots()` (Tests/Shots.swift) start with
   `if ProcessInfo.processInfo.environment["GUIDE"] != nil { return guideShots(dir) }`.
3. Bundle `PokeWalker.app` as `build.sh` does, compile, then run `GUIDE=1 PokeWalker.app/Contents/MacOS/PokeWalker --shots <renders>`.
   This writes each screen as `<name>.png` at 4 px a point (`GUIDE_SCALE`), plus `<name>.json` with its words and their boxes in points.
   The run is headless: settings stay in memory, and the server is a FakeCloud.
4. Build and run the annotator here: `swiftc -O tools/guide-shots/annotate.swift -o annotate && ./annotate <renders> docs/guide/img`.
   It draws the numbers and boxes, and crops the before / after pairs.
5. Look at every picture, then update the captions if a screen changed.
