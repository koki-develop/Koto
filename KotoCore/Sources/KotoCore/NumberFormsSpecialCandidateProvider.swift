//
//  NumberFormsSpecialCandidateProvider.swift
//  Koto
//

import Foundation
import KanaKanjiConverterModule

/// 数字の入力に、丸数字やローマ数字といった「数を 1 文字で表す表記」を候補として足す。
///
/// azooKey のデフォルト辞書は全角数字(`１` = U+FF11 など)のエントリを持たず、
/// コンバータが補う追加候補もカタカナ・ひらがな・大文字を作るだけなので、
/// 数字を変換しても入力そのままの候補しか出てこない。その穴を埋める。
///
/// 出すのは Unicode に 1 文字として存在する表記だけに限る。`ⅩⅢ` のように
/// 複数文字の組み立てが必要なものは表記の揺れを持ち込むだけなので出さない。
struct NumberFormsSpecialCandidateProvider: SpecialCandidateProvider {
  func provideCandidates(
    converter _: KanaKanjiConverter,
    inputData: ComposingText,
    options _: ConvertRequestOptions
  ) -> [Candidate] {
    guard let number = Self.parseNumber(inputData.convertTarget) else {
      return []
    }

    return NumberForm.allCases
      .compactMap { $0.text(for: number) }
      .map { Self.makeCandidate(text: $0, inputData: inputData) }
  }

  /// 変換対象を数値として解釈する。数字だけからなる文字列でなければ nil。
  ///
  /// Koto は入力を全角に直してから `ComposingText` に載せる(`ComposingText.append`)ため
  /// 通常は全角数字が渡ってくるが、`.direct` 入力など半角のまま届く経路もあるので両方受ける。
  private static func parseNumber(_ convertTarget: String) -> Int? {
    guard !convertTarget.isEmpty else {
      return nil
    }

    var digits = ""
    for character in convertTarget {
      guard let digit = Self.halfWidthDigit(character) else {
        return nil
      }
      digits.append(digit)
    }

    // `０１` のような先頭ゼロ付きは数の表記とみなさない。
    guard digits.count == 1 || digits.first != "0" else {
      return nil
    }

    // 桁数が Int に収まらないほど多い場合はここで nil になる。
    return Int(digits)
  }

  private static let halfWidthDigits: [Character] = Array("0123456789")

  /// 半角・全角の数字を半角に揃える。数字でなければ nil。
  private static func halfWidthDigit(_ character: Character) -> Character? {
    guard character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first
    else {
      return nil
    }

    switch scalar.value {
    case 0x30...0x39:  // 半角数字
      return character
    case 0xFF10...0xFF19:  // 全角数字
      return Self.halfWidthDigits[Int(scalar.value - 0xFF10)]
    default:
      return nil
    }
  }

  private static func makeCandidate(text: String, inputData: ComposingText) -> Candidate {
    let value: PValue = -10
    let ruby = inputData.convertTarget.toKatakana()

    return Candidate(
      text: text,
      value: value,
      composingCount: .inputCount(inputData.input.count),
      lastMid: MIDData.一般.mid,
      data: [
        DicdataElement(
          word: text,
          ruby: ruby,
          cid: CIDData.固有名詞.cid,
          mid: MIDData.一般.mid,
          value: value
        )
      ],
      // 学習させると選んだ表記が学習辞書に載り、次からは辞書由来の候補として
      // 先頭に来てしまう。数字を変換しただけで `①` が既定になるのは事故なので、
      // この候補は学習の対象から外す。
      isLearningTarget: false
    )
  }
}

/// 数を 1 文字で表す Unicode の系列。宣言順がそのまま候補の並び順になる。
private enum NumberForm: CaseIterable {
  /// ⓪ ① ⑳ ㉑ ㊿
  case circled
  /// ⓿ ❶ ⓫ ⓴
  case negativeCircled
  /// Ⅰ Ⅻ
  case romanUpper
  /// ⅰ ⅻ
  case romanLower

  /// `number` に対応する文字。その系列に存在しない数なら nil。
  func text(for number: Int) -> String? {
    switch self {
    case .circled:
      // ⓪ と ①〜⑳ と ㉑〜㉟ と ㊱〜㊿ はそれぞれ別のブロックに分かれている。
      switch number {
      case 0:
        return Self.character(0x24EA)
      case 1...20:
        return Self.character(0x2460, offsetBy: number - 1)
      case 21...35:
        return Self.character(0x3251, offsetBy: number - 21)
      case 36...50:
        return Self.character(0x32B1, offsetBy: number - 36)
      default:
        return nil
      }

    case .negativeCircled:
      // ❶〜❿ は Dingbats、⓿ と ⓫〜⓴ は Enclosed Alphanumerics にある。
      switch number {
      case 0:
        return Self.character(0x24FF)
      case 1...10:
        return Self.character(0x2776, offsetBy: number - 1)
      case 11...20:
        return Self.character(0x24EB, offsetBy: number - 11)
      default:
        return nil
      }

    case .romanUpper:
      // 1 文字で表せるのは Ⅰ〜Ⅻ まで(この先は Ⅼ=50, Ⅽ=100, … と飛ぶ)。
      guard (1...12).contains(number) else {
        return nil
      }
      return Self.character(0x2160, offsetBy: number - 1)

    case .romanLower:
      guard (1...12).contains(number) else {
        return nil
      }
      return Self.character(0x2170, offsetBy: number - 1)
    }
  }

  private static func character(_ base: UInt32, offsetBy offset: Int = 0) -> String? {
    guard let scalar = Unicode.Scalar(base + UInt32(offset)) else {
      return nil
    }
    return String(scalar)
  }
}
