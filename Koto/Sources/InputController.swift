//
//  InputController.swift
//  Koto
//
//  Created by koki sato on 2024/09/15.
//

import InputMethodKit

@objc(KotoInputController)
class KotoInputController: IMKInputController {
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        return false
    }
}
