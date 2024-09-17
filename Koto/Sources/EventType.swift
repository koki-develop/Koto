//
//  EventType.swift
//  Koto
//
//  Created by koki sato on 2024/09/16.
//

import AppKit

enum EventType {
  case enter
  case space
  case backspace
  case esc

  case left
  case right
  case down
  case up

  case input(_ text: String)
}

func getEventType(_ event: NSEvent) -> EventType? {
  switch event.keyCode {
  case 36:
    return .enter
  case 49:
    return .space
  case 51:
    return .backspace
  case 53:
    return .esc

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

  case 123:
    return .left
  case 124:
    return .right
  case 125:
    return .down
  case 126:
    return .up

  default:
    break
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
