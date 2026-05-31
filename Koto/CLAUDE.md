# CLAUDE.md — Koto (app target)

A thin bootstrap: `App.swift` starts the `IMKServer`, and `Info.plist` declares the input mode. All IME logic lives in the `KotoCore` package (see `KotoCore/CLAUDE.md`).

**Gotcha:** `Info.plist`'s `InputMethodServerControllerClass` must match the `@objc` name of `KotoInputController` in `KotoCore`. Renaming the controller without updating this key makes macOS fail to instantiate the IME.
