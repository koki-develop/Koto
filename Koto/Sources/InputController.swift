//
//  InputController.swift
//  Koto
//
//  Created by koki sato on 2024/09/15.
//

import InputMethodKit

@objc(KotoInputController)
class KotoInputController: IMKInputController {
  private let inputSubject 

  override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
    super.init(server: server, delegate: delegate, client: inputClient)
  }

  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    return false
  }
}
