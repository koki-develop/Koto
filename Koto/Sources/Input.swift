//
//  Input.swift
//  Koto
//
//  Created by koki sato on 2024/09/16.
//

import AppKit

class Input {
  let eventType: EventType
  let event: NSEvent?

  init(eventType: EventType, event: NSEvent? = nil) {
    self.eventType = eventType
    self.event = event
  }
}

func inputFromEvent(event: NSEvent) -> Input? {
  guard let eventType = getEventType(event) else {
    return nil
  }

  return Input(eventType: eventType, event: event)
}
