import AppKit
import Carbon
import InputMethodKit

/// `IMKTextInput` のテスト用スタブ。
///
/// 本物のクライアントはプロセス外にいて、呼び出しは同期 XPC になる。
/// ここでは呼び出しを記録するだけにして、「クライアントを何回叩いたか」
/// 「叩いた時点でコントローラがどんな状態だったか」を検査できるようにする。
final class FakeTextInput: NSObject, IMKTextInput {
  enum Call: Equatable {
    case insertText(String)
    case setMarkedText(String)
    case cursorRect
  }

  private(set) var calls: [Call] = []

  /// 呼び出しのたびに実行される。呼び出し時点のコントローラの状態を覗くのに使う。
  var onCall: ((Call) -> Void)?

  private func record(_ call: Call) {
    self.calls.append(call)
    self.onCall?(call)
  }

  private static func text(from value: Any?) -> String {
    switch value {
    case let value as String:
      return value
    case let value as NSAttributedString:
      return value.string
    default:
      return ""
    }
  }

  // MARK: - Koto が使うもの

  func insertText(_ string: Any!, replacementRange: NSRange) {
    self.record(.insertText(Self.text(from: string)))
  }

  func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
    self.record(.setMarkedText(Self.text(from: string)))
  }

  func attributes(
    forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!
  ) -> [AnyHashable: Any]! {
    self.record(.cursorRect)
    lineRect?.pointee = NSRect(x: 0, y: 0, width: 1, height: 16)
    return [:]
  }

  // MARK: - Koto は使わないが、プロトコル適合に必要なもの

  func selectedRange() -> NSRange {
    return NSRange(location: NSNotFound, length: 0)
  }

  func markedRange() -> NSRange {
    return NSRange(location: NSNotFound, length: 0)
  }

  func attributedSubstring(from range: NSRange) -> NSAttributedString! {
    return NSAttributedString()
  }

  func length() -> Int {
    return 0
  }

  func characterIndex(
    for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
    inMarkedRange: UnsafeMutablePointer<ObjCBool>!
  ) -> Int {
    return NSNotFound
  }

  func validAttributesForMarkedText() -> [Any]! {
    return []
  }

  func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}

  func selectMode(_ modeIdentifier: String!) {}

  func supportsUnicode() -> Bool {
    return true
  }

  func bundleIdentifier() -> String! {
    return "me.koki.inputmethod.Koto.tests"
  }

  func windowLevel() -> CGWindowLevel {
    return 0
  }

  func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool {
    return false
  }

  func uniqueClientIdentifierString() -> String! {
    return "fake-client"
  }

  func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
    return ""
  }

  func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect {
    return .zero
  }
}
