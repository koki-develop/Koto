//
//  EventType.swift
//  Koto
//
//  Created by koki sato on 2024/09/16.
//

import AppKit

enum EventType {
  case ignore

  case enter
  case space
  case backspace
  case esc

  case shiftLeft
  case shiftRight

  case down
  case up

  case input(_ text: String)
}

func getEventType(_ event: NSEvent) -> EventType? {
  if event.modifierFlags.contains(.command) {
    return nil
  }

  switch event.keyCode {
  case 36:
    return .enter
  case 49:
    return .space
  case 51:
    return .backspace
  case 53:
    return .esc

  case 4:  // h
    if event.modifierFlags.contains(.control) {
      return .backspace
    }
    break

  case 35:  // p
    if event.modifierFlags.contains(.control) {
      return .up
    }
    break
  case 45:  // n
    if event.modifierFlags.contains(.control) {
      return .down
    }
    break

  case 123:  // ←
    if event.modifierFlags.contains(.shift) {
      return .shiftLeft
    }
    return .ignore
  case 124:  // →
    if event.modifierFlags.contains(.shift) {
      return .shiftRight
    }
    return .ignore
  case 125:  // ↓
    return .down
  case 126:  // ↑
    return .up

  default:
    break
  }

  if event.modifierFlags.contains(.control) {
    return .ignore
  }

  if let text = event.characters, isPrintable(text) {
    return .input(text)
  }

  return nil
}

private func isPrintable(_ text: String) -> Bool {
  let printable = [
    CharacterSet.alphanumerics,
    CharacterSet.symbols,
    CharacterSet.punctuationCharacters,
  ].reduce(CharacterSet()) { $0.union($1) }
  return !text.unicodeScalars.contains(where: { !printable.contains($0) })
}
