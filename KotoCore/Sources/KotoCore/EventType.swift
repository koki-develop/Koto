//
//  EventType.swift
//  Koto
//
//  Created by koki sato on 2024/09/16.
//

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
