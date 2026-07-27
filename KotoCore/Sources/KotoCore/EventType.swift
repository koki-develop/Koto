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

  /// テンキー以外で入力された ASCII 数字(0〜9)。
  /// 候補選択中は候補の番号選択に使い、それ以外の状態では通常の文字入力として扱う。
  ///
  /// キーコードではなく実際に入力された文字で判定するため、キーボードレイアウトに
  /// 依存しない。最上段が Shift 併用でしか数字を出さないレイアウト(AZERTY など)でも、
  /// QWERTY と同じく「選択中の数字入力は候補の確定」になる。
  case number(_ value: Int)

  case input(_ text: String)
}
