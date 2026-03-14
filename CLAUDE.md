# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Koto is a macOS Japanese Input Method Editor (IME) written in Swift using Apple's `InputMethodKit` framework. It uses `KanaKanjiConverterModuleWithDefaultDictionary` (azooKey-based) for kana-to-kanji conversion. Distributed as a `.pkg` installer via Homebrew Cask.

## Build & Development Commands

Requires [Task](https://taskfile.dev) CLI runner.

| Command | Description |
|---------|-------------|
| `task build` | Debug build (no code signing) |
| `task build:release` | Release build |
| `task install` | Debug build + install to `~/Library/Input Methods` |
| `task install:release` | Release build + install |
| `task uninstall` | Remove from Input Methods and kill process |
| `task stop` | `pkill Koto` |
| `task clean` | Remove `./build` directory |
| `task fmt` | Format with `swift-format --recursive --in-place .` |

No test suite exists.

## Architecture

### State Machine

The IME operates as a three-state machine (`InputState.swift`):
- **`.normal`** → No active input
- **`.composing`** → Romaji being typed, converted to kana in real-time
- **`.selecting`** → Candidate list visible for kanji selection

### Core Components

- **`App.swift`** — `@main` entry point. Sets up `IMKServer` connecting the IME to macOS.
- **`InputController.swift`** — Central event handler (`IMKInputController` subclass). Routes `NSEvent` through `(EventType, InputState)` pattern matching to determine actions. This is the main logic hub.
- **`EventType.swift`** — Classifies keyboard events (printable, space, enter, backspace, arrows, etc.).
- **`KeyCodes.swift`** — Raw macOS key code constants.

### Extensions (wrapping third-party types)

- **`ComposingText.swift`** — Romaji-to-kana conversion with halfwidth→fullwidth mapping and "ん" edge case handling.
- **`KanaKanjiConverter.swift`** — Configures converter with `ja_JP`, manages learning data persistence in user caches directory.

### Key Event Routing (InputController)

The `handle(_:client:)` method dispatches based on `(EventType, InputState)` tuples. Key behaviors:
- Printable chars in normal/composing → append to `ComposingText`
- Space/Down in composing → switch to `.selecting`
- Enter in composing → insert as-is; in selecting → confirm candidate
- Ctrl+K → convert to katakana
- Shift+Left/Right in selecting → resize conversion segment

## CI/CD

- **`ci.yml`** — Builds for arm64+x86_64, packages as `Koto.pkg`
- **`release-please.yml`** — Automated releases: builds pkg, uploads to GitHub Release, updates Homebrew Cask
- **`github-actions-lint.yml`** — Lints workflows with `actionlint`/`ghalint`/`zizmor`
