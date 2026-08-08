//
//  Log.swift
//  Koto
//

import Foundation
import os

/// ログの出し先。
///
/// 入力メソッドの不具合は、利用者の環境で起きたものを後から追うしかない。
/// `NSLog` は unified log 上で本文が `<private>` に伏せられて読めなくなるため、
/// `os.Logger` を使い、公開してよい情報だけを明示的に `.public` で出す。
///
/// **入力内容(未確定文字列・変換候補・確定文字列)は決してログに載せない。**
/// 載せてよいのは入力セッションのライフサイクルと、処理の所要時間だけ。
enum Log {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "me.koki.inputmethod.Koto"

  /// activate / deactivate など入力セッションのライフサイクル。
  static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")

  /// クライアント(入力先アプリ)への同期呼び出し。
  static let client = Logger(subsystem: subsystem, category: "client")

  /// 学習メモリの置き場に対する後始末。
  static let memory = Logger(subsystem: subsystem, category: "memory")
}
