# CLAUDE.md — Koto (app target)

A thin bootstrap. `App.swift` starts the `IMKServer` and handles the process lifecycle; `Info.plist` declares the input mode. All IME logic lives in the `KotoCore` package (see `KotoCore/CLAUDE.md`).

**Gotcha:** `Info.plist`'s `InputMethodServerControllerClass` must match the `@objc` name of `KotoInputController` in `KotoCore`. Renaming the controller without updating this key makes macOS fail to instantiate the IME.

**Gotcha:** create exactly one `IMKServer`, in `applicationDidFinishLaunching`. `IMKServer.h` states an input method should create one and only one.

## Process lifecycle

Two requirements shape `App.swift`. Both are easy to undo by accident.

**Whatever `KotoCore` is holding must be written out before the process ends — including when it is killed.** `applicationWillTerminate` alone is not enough: AppKit does not run it for SIGTERM, and SIGTERM is how the IME actually dies in practice (`task stop`, `task uninstall`, replacing the app via the Cask, removing the input source).

**Taking over SIGTERM must not make a wedged IME unkillable.** Handling the signal means losing its default disposition, and this process can have its main thread blocked for seconds at a time by a client call (see `KotoCore/CLAUDE.md`). A handler that depends on the main thread being responsive is worse than no handler at all — the user is left with a frozen input method that ignores `pkill`. The handler is built so that termination never depends on the main thread; read it before changing it.

**Startup does the expensive work.** `KotoInputController.preload()` builds the converter at launch, when nothing is waiting on us, rather than letting the first focus transition pay for the dictionary load.
