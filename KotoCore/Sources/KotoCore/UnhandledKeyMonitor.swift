//
//  UnhandledKeyMonitor.swift
//  Koto
//

import AppKit
import CoreGraphics

/// 打ったのに何も起きなかった理由。
///
/// 「何も起きない」には 2 通りある。アプリへ素通しした場合と、Koto が握り潰した場合。
/// 利用者から見ればどちらも同じなので、まとめて扱う。
enum UnhandledKeyReason: String {
  case notKeyDown = "not a key-down event"
  case commandModifier = "command modifier is set"
  case noCharacters = "event has no characters"
  /// 文字が空、または画面に出ない文字しか無い。
  case notPrintable = "no printable characters"
  case noActionForState = "nothing to do in the current state"
  /// 変換中に飛んできた、Koto の割り当てにない修飾キーの組み合わせ。握り潰す。
  case ignoredCombination = "ignored key combination"
}

/// 打鍵が実を結ばなかったことの記録係。
///
/// 何も起きないこと自体は正常でもある(⌘ を伴うショートカット、ファンクションキー、
/// いまの状態ですることが無いキー、変換中の未割り当ての修飾キー)。だが
/// 「Koto を選んでいるのにローマ字がそのまま入る」という不具合も、外から見える形は同じ。
/// 両者を分けるのがこの型の仕事。
///
/// 分け方は回数ではなく **説明がつくかどうか**。理由が修飾キーなら、その修飾キーが
/// 本当に押されているかを問い合わせれば裏が取れる。名乗っているのに押されていなければ、
/// 押されていない修飾キーがイベントに乗り続けている状態 — キーの取りこぼしが残す形であり、
/// 説明にはならない。
///
/// **入力内容は載せない。** 記録するのは理由と修飾キーの状態まで。どのアプリで起きたかは
/// 載せない。バンドル ID の取得はクライアントへの 1 往復で、それを入力経路に足すのは
/// 「省ける呼び出しは省く」に反する(`Client` 参照)。どのアプリだったかは利用者が言える。
struct UnhandledKeyMonitor {
  /// 説明になりうる修飾キー。押されていれば、そのキーはもともと Koto のものではない。
  private static let explanatoryModifiers: NSEvent.ModifierFlags = [.command, .control]

  /// これだけ説明のつかない打鍵が続いたら異常とみなす。
  ///
  /// 1 回で鳴らさないのは、イベントを見る時点が実際の打鍵より少し後になるため。
  /// ⌘ を素早く離すと、見たときには既に離れていて「名乗っている修飾キーが
  /// 押されていない」形になりうる。不具合のほうは打つ限り延々と続くので、
  /// 数回ぶん待っても取り逃さない。
  private static let threshold = 3

  /// いま実際に押されている修飾キーの取得口。
  ///
  /// 差し替えられるようにしてあるのはテストのため。実キーの状態に依存したままだと、
  /// テストの結果が「走らせた人がそのとき何を押していたか」で変わる。
  var heldModifiers: () -> NSEvent.ModifierFlags = UnhandledKeyMonitor.systemHeldModifiers

  /// 説明のつかない打鍵が何回続いているか。
  /// 読めるようにしてあるのはテストのため。
  private(set) var unexplainedRun = 0

  /// 打鍵が実を結ばなかったことを記録する。
  mutating func record(_ reason: UnhandledKeyReason, event: NSEvent) {
    let claimed = event.modifierFlags.intersection(Self.explanatoryModifiers)
    // 押下状態の問い合わせは、修飾キーを名乗っているときだけ。判定と記録で同じ値を使う。
    let held = claimed.isEmpty ? nil : self.heldModifiers().intersection(Self.explanatoryModifiers)

    guard !Self.isExplained(reason, event, claimed: claimed, held: held) else {
      // 説明がついた時点で連続は途切れている。戻さないと、いくらでも離れた時刻の
      // 無関係な単発が積み上がって、閾値の「連続」が意味を失う。
      // 単に 0 を代入するのではなく `endRun` を通すこと。記録済みの連続なら、
      // 終わったことも残さないと 2 本で挟めない。
      self.endRun()
      Log.event.info("unhandled key, expected: \(reason.rawValue, privacy: .public)")
      return
    }

    self.unexplainedRun += 1
    // 記録は 1 本の連続につき 1 回だけ。閾値をまたいだ瞬間にしか出さない。
    let run = self.unexplainedRun
    guard run == Self.threshold else {
      Log.event.info("unhandled key, unexplained: \(reason.rawValue, privacy: .public)")
      return
    }

    let heldDescription = held.map { "0x" + String($0.rawValue, radix: 16) } ?? "not queried"
    Log.event.error(
      """
      \(run, privacy: .public) keys in a row did nothing, with no explanation: \
      \(reason.rawValue, privacy: .public), \
      eventModifiers=0x\(String(event.modifierFlags.rawValue, radix: 16), privacy: .public), \
      heldModifiers=\(heldDescription, privacy: .public)
      """
    )
  }

  /// 連続が途切れたときに呼ぶ。異常として記録した連続なら、終わったことも残す。
  ///
  /// キーが実を結んだときだけでなく、入力セッションが終わるときにも呼ぶこと。
  /// 「打っても入らないので別のアプリへ移る」が利用者の自然な反応なので、
  /// そこで呼ばないと発生の終わりが記録されず、規模も長さも読めなくなる。
  mutating func endRun() {
    let run = self.unexplainedRun
    self.unexplainedRun = 0
    guard run >= Self.threshold else {
      return
    }
    Log.event.error(
      "run of keys doing nothing ended after \(run, privacy: .public) unexplained keys")
  }

  /// その打鍵に説明がつくか。
  ///
  /// - Parameters:
  ///   - claimed: イベントが名乗っている、説明になりうる修飾キー。
  ///   - held: いま実際に押されている、説明になりうる修飾キー。
  ///     `claimed` が空で問い合わせる必要が無かったときは `nil`。
  private static func isExplained(
    _ reason: UnhandledKeyReason, _ event: NSEvent,
    claimed: NSEvent.ModifierFlags, held: NSEvent.ModifierFlags?
  ) -> Bool {
    switch reason {
    case .notKeyDown, .noCharacters:
      // IMK が渡してくるのは keyDown だけで、keyDown は文字を持つ。どちらも起きないはず。
      return false
    case .notPrintable:
      // ファンクションキーやタブ、文字を生まないキー。もともとアプリのもの。
      return true
    case .commandModifier, .noActionForState, .ignoredCombination:
      guard !claimed.isEmpty else {
        // 修飾キーを名乗っていないなら、説明になるのは「打った文字が無かった」ことだけ。
        // Enter や矢印のように文字を持たないキーはここで説明がつく。
        // 文字を持つキーが実を結ばないのが、まさに不具合の形。
        return !Self.hasPrintableCharacters(event)
      }
      // 名乗っている修飾キーが本当に押されているか。押されていなければ説明にならない。
      return claimed.isSubset(of: held ?? [])
    }
  }

  /// いま押されている修飾キー。
  ///
  /// `.combinedSessionState` は、物理キーの状態に加えて、プログラムから流し込まれた
  /// イベントぶんも含む。`.hidSystemState` にすると、自動化ツールが送った ⌘ 付きの
  /// キーが「押されていない ⌘ を名乗っている」と読まれて偽の発生になる。
  /// 捕まえたいのは「どこにも押されていないのにイベントだけが名乗っている」ほうなので、
  /// 広く取るほうが正しい。
  ///
  /// `CGEventFlags` と `NSEvent.ModifierFlags` は同じビットを使うので、そのまま詰め替える。
  private static func systemHeldModifiers() -> NSEvent.ModifierFlags {
    let held = CGEventSource.flagsState(.combinedSessionState)
    return NSEvent.ModifierFlags(rawValue: UInt(held.rawValue))
  }

  private static func hasPrintableCharacters(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown || event.type == .keyUp else {
      // characters は key イベント以外に送ると例外を投げる。
      return false
    }
    guard let text = event.characters else {
      return false
    }
    return isPrintable(text)
  }
}
