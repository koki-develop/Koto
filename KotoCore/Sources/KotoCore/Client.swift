//
//  Client.swift
//  Koto
//

import Foundation
import InputMethodKit

/// クライアント(入力先アプリ)への同期呼び出しをまとめて受け持つ。
///
/// `IMKTextInput` のメソッドはいずれもクライアントプロセスへの同期 XPC で、
/// 相手が応答しなければ IMK が諦めるまで入力メソッドのメインスレッドが止まる。
/// 止まっている間は IMK からの要求が一切処理されないため、入力メソッドが丸ごと
/// 無反応になり、打鍵はアプリへ素通しされる。
///
/// **どのコールバックから呼んでよいかには規約がある。KotoCore/CLAUDE.md を参照。**
///
/// 呼び出しをこの型に集約しているのは、規約を破る箇所を見つけやすくするためと、
/// 所要時間を 1 か所で計測して閾値超えを記録するため。入力メソッドの不調は
/// 利用者の環境でしか再現しないので、痕跡が残ることに意味がある。
struct Client {
  /// これを超えたら異常とみなす所要時間(ミリ秒)。
  private static let slowCallThreshold: Double = 50

  private let textInput: any IMKTextInput

  /// 各コールバックが渡してくる client を包む。
  ///
  /// `IMKInputController.client()` ではなくコールバックの引数を使うこと。
  /// 前者はコントローラが保持する ivar で、いつ更新されるかの保証がない。
  init?(_ sender: Any?) {
    guard let textInput = sender as? any IMKTextInput else {
      return nil
    }
    self.textInput = textInput
  }

  /// 未確定文字列を差し替える。空文字列を渡すと未確定文字列が消える。
  func setMarkedText(_ text: Any) {
    self.measure("setMarkedText") {
      self.textInput.setMarkedText(text, selectionRange: .notFound, replacementRange: .notFound)
    }
  }

  /// 文字列を確定して挿入する。未確定文字列があれば置き換わるため、
  /// 続けて `setMarkedText("")` を呼ぶ必要はない。
  func insertText(_ text: String) {
    self.measure("insertText") {
      self.textInput.insertText(text, replacementRange: .notFound)
    }
  }

  /// 未確定文字列の先頭のスクリーン座標。候補ウィンドウの配置基準に使う。
  func cursorRect() -> NSRect {
    var rect = NSRect.zero
    self.measure("attributes(forCharacterIndex:)") {
      _ = self.textInput.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
    }
    return rect
  }

  private func measure(_ name: String, _ body: () -> Void) {
    measureElapsed(
      "client call \(name)", threshold: Self.slowCallThreshold, log: Log.client, body)
  }
}
