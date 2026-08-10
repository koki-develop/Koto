# CLAUDE.md — KotoCore (IME logic)

Local SwiftPM package containing all IME logic. Sources live in `Sources/KotoCore/`.

## Dependency

`AzooKeyKanaKanjiConverter` is declared in `Package.swift`, pinned by revision. Update the dependency here, not in the Xcode project.

**Gotcha:** the `KotoCore` library product must stay automatic/static. Making it a dynamic framework breaks bundling of the converter's default dictionary resource into the app.

## Tests

`Tests/KotoCoreTests/` (swift-testing, `@testable import KotoCore`). Run with `swift test` from this directory. Not wired into `task` or CI, so run it by hand after touching conversion logic.

**Never let a test convert with the default `options()`.** Conversion reads and writes the learning memory and reads the user dictionary, both under `~/Library/Application Support/Koto` by default — a test that uses them corrupts real learning data and turns its own assertions into a function of the developer's typing history. Shared fixtures live in `TestSupport.swift` (`makeController`, `makeThrowawayConverter`, `makeCandidate`, `makeKeyEvent`); build on those rather than copying a controller factory into a new file, because the copy that forgets to substitute the converter fails silently and takes the developer's learning data with it.

**Do not assert on wall-clock timing.** swift-testing runs tests in parallel and most of these are `@MainActor`, so a test that waits a fixed span measures whichever other test happens to hold the main actor. Widening the wait to compensate is worse than the flake: `repeatedUpdatesDoNotExtendTheDeadline` was once relaxed that way and went on passing with the very regression it exists to catch. Timing *policy* is a pure function (`Converter.saveSchedule`) and is tested by calling it; only `debouncedSaveFires` waits at all, and only to confirm the scheduled task runs.

**Anything that reads live machine state has to be injectable.** `UnhandledKeyMonitor.heldModifiers` defaults to the live modifier state but is a closure, so tests fix it — otherwise the result depends on what the person running them happened to be holding down.

`FakeTextInput` records what the controller does to its client. Use it to assert how many times the client is called and what state the controller was in at each call.

## Orientation

- The IME is a three-state machine (`InputState`): `.normal` (idle) → `.composing` (typing romaji) → `.selecting` (candidate list shown).
- `InputController` (`@objc(KotoInputController)`, an `IMKInputController` subclass) is the logic hub. `handle(_:client:)` reads the event with `interpret`, then `dispatch` runs the `(EventType, InputState)` state machine — start there to follow any input behavior.
- `Client` is the only thing that talks to the client app. `Converter` wraps the kana-kanji converter and owns when learning data is persisted. `UnhandledKeyMonitor` decides whether a key that produced nothing is worth recording.

## Talking to the client

Every `IMKTextInput` method is a **synchronous XPC call into the client app**, and if the client does not answer, the IME's main thread blocks until IMK gives up. While it is blocked *no* IMK request is served — `activateServer` and `handle` for the app you just switched to are queued and keystrokes fall through raw, so the user sees "Koto is selected but only alphanumerics come out". Every avoidable call is an avoidable chance of that.

The invariant:

> **Synchronous client calls belong inside `handle(_:client:)`.** There the client is the one waiting on us for a key-event reply, so it is alive and awake. `activateServer` and `deactivateServer` must not touch the client at all — they run mid focus-transition, when the client is busy with its own work.

`commitComposition` is the one unavoidable exception: IMK calls it at focus loss and pending text has to go somewhere. It is written to the strictest form the invariant allows — everything that does not need the client happens first, and the client is touched at most once, only when there is something to send. Read the function before changing it; the ordering is load-bearing.

**The floor is not zero.** Even with Koto touching nothing, `super.activateServer` and `super.deactivateServer` each make one client round-trip of IMK's own: the unified log emits `(InputMethodKit) Get bundle identifier` 1:1 with `Activate Server` / `Deactivate Server` in Koto's process, and that activity is IMK's trace of `-[IMKTextInput bundleIdentifier]`. Koto cannot skip it, so both `super` calls are wrapped in `measureCallback` — if a focus transition stalls, the log says whether the time went into IMK's round-trip or into Koto's own work.

Two rules that follow from the same invariant:

- **Reach for the `client` the callback handed you before `IMKInputController.client()`.** Apple documents the latter only as an ivar; nothing promises it is current. Two places have to use it anyway: the candidate window's mouse-click delegate, which IMK hands no client at all, and `commitComposition`, which falls back to it rather than drop pending text on the floor.
- **Prefer the call you can skip.** Merging two writes into one, or skipping a write with nothing to say, is not micro-optimization here — it is the only lever on how long the IME can stall.

## Keys that do nothing

A keystroke can fail to produce anything in two ways: `handle` returns `false` and the app gets the key raw, or Koto swallows it and nobody gets it. The user cannot tell those apart — both are "I typed and nothing happened" — and **the first is the exact shape of "Koto is selected but only romaji comes out"**. `handle` is split so the decisions stay separate: `interpret` turns an event into either an `EventType` or an `UnhandledKeyReason`, and `dispatch` runs the state machine and answers with a `DispatchOutcome`.

**`false` from `handle` does not mean "Koto did nothing", and `true` does not mean it did something useful.** `(.backspace, .selecting)` commits the pending text *and* lets the app delete — `.handledAndForwarded`. `(.ignore, .composing)` swallows an unassigned modifier combination so it cannot corrupt the composition — `.swallowed`, which returns `true` but is still recorded. Collapsing these into a `Bool` made the monitor label a key it had just written to the client as "nothing to do in the current state", and made a `control` stuck mid-composition invisible: every letter became `.ignore`, vanished, and closed the run instead of extending it.

Doing nothing is also completely normal: ⌘-shortcuts, function keys, Enter with nothing composed, an unassigned ⌃-combination during composition. Counting consecutive occurrences does *not* separate the two — five tabs through a form reach any plausible threshold. `UnhandledKeyMonitor` asks a different question: **is this explained?**

- No printable characters (tab, function keys, arrows, Enter) — explained. The key was never Koto's.
- The event claims ⌘ or `control` — explained *only if that modifier is actually held*, checked against `CGEventSource.flagsState(.combinedSessionState)`. A modifier asserted on an event while asserted nowhere else is what a dropped key-up leaves behind, which is a live possibility with a key remapper posting through a virtual HID device. **Use the combined state, not `.hidSystemState`** — automation tools post ⌘-shortcuts with no key physically down, and reading hardware only turns every one of those into a false incident.
- Printable characters and no modifier at all — never explained. That is the bug's exact shape.
- `.notKeyDown` / `.noCharacters` — never explained. IMK sends only key-downs, and key-downs carry characters.

Unexplained keys are counted; the count is what tolerates the one-off case where the modifier was released between the keystroke and our look at the modifier state. Crossing the threshold logs `error`, and `endRun` logs the streak's length. **Everything that breaks the streak must go through `endRun`** — a key that did something, an *explained* one, and `deactivateServer` / `commitComposition`, because "it stopped working so I switched apps" is the likeliest way an incident ends. Zeroing the counter directly instead would leave an opened incident unclosed; letting an explained key skip the reset would let unrelated one-offs hours apart add up to a false alarm whose reported size and duration are both fiction. Two `error` lines bracket an incident, giving its size and duration.

**`isPrintable("")` is `false`, and that is load-bearing.** Written as "contains no unprintable scalar" it is vacuously `true` for the empty string, and a key whose `characters` is empty then becomes `.input("")`: the controller enters `.composing`, sends an empty `setMarkedText`, and returns `true`. The key reaches neither the app nor the monitor — it disappears. The predicate answers "is there text here", so the empty case belongs in the predicate, not in each caller.

**Never widen these lines to the key itself** — the reason and the modifier states are enough, and key codes are input content. They also carry no bundle id: fetching it is a client round-trip, and adding one to the key path contradicts the rule above. Which app it was is something the user can say.

**IMK traces the other direction for free.** In the IME's own process it emits an activity per client call — `Setting marked text`, `Inserting text`, `Get attributes for character`, `Activate Server`, `Deactivate Server`. `log show --predicate 'process == "Koto"' --info --debug` reads them back, so "was Koto handling keys when the user says it broke?" is answerable after the fact without adding anything.

## Learning data

`Converter` decides when learning data is written to disk, and that is a real decision, not a detail. Persisting is a whole-memory read-merge-write that blocks the main thread, so:

- **It must never run on the focus-transition path.** Putting it in `deactivateServer` means paying it on every single app switch, inside exactly the window described above.
- **It must not be postponed indefinitely either**, or a crash or `pkill` takes the whole session's learning with it. `Converter` bounds the delay; see its declaration.
- **Only schedule it when something was actually learned.** azooKey drops candidates with `isLearningTarget: false` — the injected number forms and its own special conversions — so scheduling on those rewrites a memory that did not change.

`KanaKanjiConverter` is a non-`Sendable` `final class`, so moving the save to a background queue is not an option — do not try.

Two pieces exist so those rules can be checked without waiting on a clock. `Converter.saveSchedule` is the whole timing policy as a pure function — when to wake up, and what the deadline is — so the rules above are asserted by calling it. `ExclusiveTask` holds the pending save so that "cancel the old one before scheduling a new one" is a property of the type rather than something four call sites have to remember; forgetting it lets a stale task fire early, and that is invisible to any test that does not sleep.

### Koto owns the directory's consistency

Koto chooses where the learning memory lives, so **Koto is also responsible for the state of what is in it.** `LearningMemory.removeStaleShards(in:)` enforces that, and `Converter` is the only thing that calls it.

**azooKey merges from two places, and both have to be covered.** The obvious one is the save. The other is recovery: if a previous write was cut short, a `.pause` file is left behind and azooKey merges implicitly on the process's *first conversion*, nowhere near `save()`. So the cleanup runs in `Converter.init` as well — a crash there kills the IME before the user has typed anything.

Rather than rely on that list staying complete, the cleanup aims at a stronger invariant: **the directory is consistent whenever a merge is not actually running.** Every merge is a generation rewrite, so every merge leaves the next batch of leftovers behind — which means each one needs a cleanup on its far side, not just in front of it. `init` establishes the invariant for whatever a previous process left; `convert()` re-establishes it after the first conversion, which is where the recovery merge hides; `save()` re-establishes it after `commitUpdateLearningData()`. Enumerating merge entry points is the part that was already got wrong once; do not go back to depending on it.

**Which metadata counts as current depends on `.pause`.** Without it, `memory.memorymetadata` is the truth. With it, the truth is `memory.memorymetadata.2` — the real file may still describe the pre-interruption generation, and counting from it would delete the pending generation's tail shards, which are the only copies recovery has. Either way both `memoryN.loudstxt3` and its `.2` get dropped, because recovery restores `.2` over the real names without removing the extras.

azooKey splits the memory into one metadata file plus `memoryN.loudstxt3` shards, and rewrites only as many shards as the current generation needs — **it never deletes the ones left over when the memory shrinks.** That is not merely wasted disk: `LongTermLearningMemory.merge` sizes its read loop as `entryCount / entriesPerShard + 1`, so once the entry count lands on an exact multiple of the shard size it reads one shard past the generation. With a leftover file sitting there it walks off the end of the metadata and **the process dies on a `Data` bounds trap** (azooKey 0.11.2 has no guard on that read; `main` added one but has not shipped). The merge dies before writing, so the entry count never changes and every later save dies the same way.

Read the trap as an IME-wide failure, not a learning failure. When this process dies, every app holding an IMK session is left with a dead connection and gets no Japanese input until *it* restarts — with no visible sign that Koto was involved.

`LearningMemory` reads the entry count out of the metadata header, which is not a public format. Most of `LearningMemoryTests` cannot catch a format change — it builds the header the same way the code reads it, so the two agree no matter what azooKey does. `agreesWithLayoutWrittenByAzooKey` is the one that can: it makes azooKey write a real learning memory and checks our count against the shards actually on disk. **Keep that test working across dependency bumps** — it is the only thing standing between a format change and Koto deleting the wrong files.

The shard *size* is a second borrowed constant, and a nastier one: `DictionaryBuilder.entriesPerShard` describes the azooKey linked into this build, while the directory on disk was written by whatever build ran last. Bump the dependency across a `shardShift` change and counting with the new width would delete still-live shards — in `Converter.init`, before the user types anything. So the width is checked against the data instead of assumed: the leading shard's own header says how many entries it holds, and that must equal `min(entryCount, entriesPerShard)`. When it doesn't, the directory was written by a different layout and nothing is touched.

When in doubt, delete nothing. `LearningMemory.Generation` says which of three things the directory is, and `.unknown` means "cannot tell", never "zero shards" — zero would read as "every shard is stale" and wipe the place. Failing to delete only risks the crash this code exists to prevent; deleting too much loses learning the user cannot get back.

The one case that deletes everything is `.orphanedShards`: the metadata file is gone while numbered shards remain. Nothing can read those shards, and azooKey substitutes four zero bytes for the missing metadata and then walks off the end of them — the same process death, on every save, forever. It is reachable because `LongTermLearningMemory.reset` deletes in arbitrary order and abandons the loop on the first throw, so a failed "reset learning data" can leave exactly this. Clearing the shards finishes the interrupted reset and the next merge rebuilds from empty.

Flushing at exit is the app target's job; see `Koto/CLAUDE.md`.

## Logging

Use `Log` (`os.Logger`), not `NSLog` — `NSLog` bodies come out as `<private>` in the unified log and cannot be read back from a user's machine. Mark anything you need to read later `privacy: .public`. **Never log input content** (composing text, candidates, committed text); lifecycle transitions, timings, and why a key produced nothing.

Levels decide what survives. `error` is persisted to disk and is what a user can still hand over hours later; `info` lives in a memory buffer that rolls over in minutes. That is why `UnhandledKeyMonitor` escalates on a streak rather than logging every key at `error`. To keep the `info` trail across a reproduction:

```
sudo log config --subsystem me.koki.inputmethod.Koto --mode "level:info,persist:info"
```

## Injected candidates

`KanaKanjiConverter.swift` passes azooKey's `defaultSpecialCandidateProviders` **plus** `NumberFormsSpecialCandidateProvider`, which offers `①` `❶` `Ⅰ` `ⅰ` for digit input. The default dictionary has no entry for full-width digits, so without it `１` converts to nothing but `１`. Passing `nil` there would silently drop the custom provider and keep only the defaults.

When adding another provider, follow the same three rules:

- Emit only what exists as a single Unicode scalar. Composed strings (`ⅩⅢ`) just add spelling variants.
- Set `isLearningTarget: false`. A learned entry comes back as a *dictionary* candidate on the next conversion, which would make `①` the default result for `１`.
- Set `composingCount: .inputCount(inputData.input.count)`. It is handed to `prefixComplete(composingCount:)` on commit, so a wrong count leaves the composing text out of sync with what was committed.

## Candidate window

`CandidateWindow/` is a self-contained candidate UI. **Do not reintroduce `IMKCandidates`** — it was removed because IMK owning the candidate state caused crashes and lifecycle bugs.

- `CandidateList` is the single source of truth for candidates, selection, and the 9-row visible range. `InputController` owns it; the window only renders what it is handed.
- Scrolling lives in the model's `visibleRange`, not in an `NSScrollView`. Rendered rows and number-key (1–9) assignment are both derived from that range, so they cannot drift apart.
- `CandidateWindowController` owns an `NSPanel` (`.nonactivatingPanel`, `.popUpMenu` level) so clicks never pull focus from the host app. `show(_:at:delegate:)` needs a cursor rect from the client; `update(_:)` only redraws — use it for selection moves and scrolling to avoid a client call.
- **Ownership rule for the shared panel:** the controller that receives `activateServer` unconditionally takes it over (`takeOver(by:)`) and folds it away; only the current owner may `hide(requestedBy:)`. IMK does not order `deactivateServer` against `activateServer`, so deciding visibility by "who asked to hide" strands the panel on screen in one direction and tears it out from under a live session in the other. Decide it by "which session is active" instead.
- **The converter does not get the same treatment, deliberately.** Gating `converter.stopComposition()` on "am I still the active session" was tried and reverted. A late `deactivateServer` can only clobber a session that was just activated and has therefore composed nothing, so the gate protects nothing; meanwhile it skips the cleanup Koto owes after `takeSelectedCandidate` wrote `setCompletedData`/`updateLearningData` into the shared converter, which leaks the previous app's context into the next one — a bigram that was never typed gets learned, and a following conversion changes when the new input overlaps the old. The panel is visible state shared by *appearance*; the converter is state each session must hand back clean.
- `handle(_:client:)` syncs the panel before dispatching, so every branch may assume `.selecting` implies the panel is on screen. Number-key selection depends on that — it commits by on-screen row.
- The candidate window and the converter are process-wide singletons on `KotoInputController`. `IMKInputController` is instantiated per client app, so per-instance ones would duplicate dictionary loads and candidate panels. The controller's `converter` is settable only so tests can substitute one pointed at a throwaway directory.
