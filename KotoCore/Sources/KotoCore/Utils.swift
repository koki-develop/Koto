//
//  Utils.swift
//  Koto
//
//  Created by koki sato on 2024/09/24.
//

import Foundation
import os

/// `body` の所要時間を測り、`threshold` ミリ秒を超えていたら記録する。
///
/// 入力メソッドがメインスレッドを塞いでいる間は IMK からの要求が一切処理されず、
/// 打鍵はアプリへ素通しされる。塞いだ場所と長さが後から読めることに意味がある。
/// 不調は利用者の環境でしか再現しないので、痕跡がすべて。
func measureElapsed(_ name: String, threshold: Double, log: Logger, _ body: () -> Void) {
  let start = DispatchTime.now().uptimeNanoseconds
  body()
  let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
  if elapsed >= threshold {
    log.warning("slow: \(name, privacy: .public) took \(elapsed, privacy: .public) ms")
  }
}

/// 画面に出る文字が入っているか。
///
/// **空文字列は偽。** 呼び出し側が知りたいのは「打った文字があるか」なので、
/// 「印字できない文字を含まない」と素直に書くと空文字列で真になってしまう。真になると、
/// 文字を持たないキーが `.input("")` として未確定文字列に飲み込まれ、アプリにも届かず
/// 素通しの記録にも残らない — どこからも見えないまま消える。
func isPrintable(_ text: String) -> Bool {
  guard !text.isEmpty else {
    return false
  }
  let printable = [
    CharacterSet.alphanumerics,
    CharacterSet.symbols,
    CharacterSet.punctuationCharacters,
  ].reduce(CharacterSet()) { $0.union($1) }
  return !text.unicodeScalars.contains(where: { !printable.contains($0) })
}

/// ASCII 数字 1 文字なら 0〜9 の値を返す。全角数字や他言語の数字は対象外。
func asciiDigit(_ text: String) -> Int? {
  guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else {
    return nil
  }
  guard ("0" as Unicode.Scalar).value...("9" as Unicode.Scalar).value ~= scalar.value else {
    return nil
  }
  return Int(scalar.value - ("0" as Unicode.Scalar).value)
}
