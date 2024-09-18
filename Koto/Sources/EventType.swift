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

  case ctrlK

  case shiftLeft
  case shiftRight

  case down
  case up

  case input(_ text: String)
}

func getEventType(_ event: NSEvent, mode: InputMode) -> EventType? {
  if event.modifierFlags.contains(.command) {
    return nil
  }

  // Control key
  if event.modifierFlags.contains(.control) {
    switch event.keyCode {
    case Keycodes.h:
      return .backspace
    case Keycodes.p:
      return .up
    case Keycodes.k:
      return .ctrlK
    case Keycodes.n:
      return .down
    default:
      return .ignore
    }
  }

  // Shift key
  if event.modifierFlags.contains(.shift) {
    switch event.keyCode {
    case Keycodes.leftArrow:
      return .shiftLeft
    case Keycodes.rightArrow:
      return .shiftRight
    default:
      break
    }
  }

  switch event.keyCode {
  case Keycodes.yen:
    if mode == .en {
      return .input("\\")
    }
    break
  case Keycodes.enter:
    return .enter
  case Keycodes.space:
    return .space
  case Keycodes.backspace:
    return .backspace
  case Keycodes.escape:
    return .esc
  case Keycodes.leftArrow:
    return .ignore
  case Keycodes.rightArrow:
    return .ignore
  case Keycodes.downArrow:
    return .down
  case Keycodes.upArrow:
    return .up
  default:
    break
  }

  if let text = event.characters, isPrintable(text) {
    return .input(text)
  }

  return nil
}

// ref: https://gist.github.com/swillits/df648e87016772c7f7e5dbed2b345066
private struct Keycodes {
  static let yen: UInt16 = 0x2A
  static let enter: UInt16 = 0x4C
  static let space: UInt16 = 0x31
  static let backspace: UInt16 = 0x33
  static let escape: UInt16 = 0x35

  static let leftArrow: UInt16 = 0x7B
  static let rightArrow: UInt16 = 0x7C
  static let downArrow: UInt16 = 0x7D
  static let upArrow: UInt16 = 0x7E

  static let h: UInt16 = 0x04
  static let k: UInt16 = 0x28
  static let n: UInt16 = 0x2D
  static let p: UInt16 = 0x23
}

private func isPrintable(_ text: String) -> Bool {
  let printable = [
    CharacterSet.alphanumerics,
    CharacterSet.symbols,
    CharacterSet.punctuationCharacters,
  ].reduce(CharacterSet()) { $0.union($1) }
  return !text.unicodeScalars.contains(where: { !printable.contains($0) })
}
