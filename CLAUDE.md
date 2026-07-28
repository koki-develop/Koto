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
| `task fmt` | Format with `swift-format format --recursive --in-place .` |

Tests live in `KotoCore/Tests/` (swift-testing). Run them with `swift test` from `KotoCore/` — there is no `task` wrapper and CI does not run them.

## Project Structure

Two targets, each with its own `CLAUDE.md` covering the details:

- **`Koto/`** — the app target (`@main` entry point, `Info.plist`, entitlements, resources). See `Koto/CLAUDE.md`.
- **`KotoCore/`** — local SwiftPM package holding all IME logic. The Xcode project references it as a local package, and the external `AzooKeyKanaKanjiConverter` dependency is declared in `KotoCore/Package.swift` (pinned by revision) rather than in the Xcode project. See `KotoCore/CLAUDE.md`.

Dependency updates and IME behavior changes happen in `KotoCore`; the app target only bootstraps the `IMKServer`.

## CI/CD

- **`ci.yml`** — Builds for arm64+x86_64, packages as `Koto.pkg`
- **`release-please.yml`** — Automated releases: builds pkg, uploads to GitHub Release, updates Homebrew Cask
- **`github-actions-lint.yml`** — Lints workflows with `actionlint`/`ghalint`/`zizmor`
