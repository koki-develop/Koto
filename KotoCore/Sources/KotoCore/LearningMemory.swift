//
//  LearningMemory.swift
//  Koto
//

import Foundation
import KanaKanjiConverterModule

/// 学習メモリの置き場の辻褄合わせ。
///
/// azooKey は学習メモリを「全エントリぶんのメタデータ 1 本」と、
/// `DictionaryBuilder.entriesPerShard` 件ごとに分けた `memoryN.loudstxt3` で持つ。
/// 保存のたびに必要な数だけシャードを書き直すが、**前回より数が減ったときに
/// 余ったシャードを消さない**。学習は古い項目を落として縮むので、置き場には
/// いずれ前世代の取り残しが溜まる。
///
/// 取り残しは容量の無駄では済まない。`LongTermLearningMemory.merge` は読むシャードの数を
/// `entryCount / entriesPerShard + 1` で決めるため、エントリ数がちょうど
/// `entriesPerShard` の倍数になった保存以降、実在する世代より 1 つ多く読みにいく。
/// そこに取り残しがあると、メタデータを持たないエントリのぶんまでメタデータを
/// 読み進めてファイル末尾を越え、`Data` の範囲外アクセスで **プロセスが即死する**
/// (azooKey 0.11.2 のこのループには境界チェックが無い)。しかも merge は書き込みの前に
/// 落ちるためエントリ数が変わらず、以後の保存が永久に落ち続ける。
///
/// 入力メソッドの死は学習の巻き添えでは済まない。プロセスが落ちると、その時点で
/// セッションを張っていたアプリは死んだ接続を掴んだまま取り残され、そのアプリでは
/// 再起動するまで日本語入力ができなくなる。
///
/// 置き場を用意しているのは Koto なので、その中身の辻褄も Koto が合わせる。
enum LearningMemory {
  private static let metadataFileName = "memory.memorymetadata"
  /// 書き込みが中断されたとき、次のマージの冒頭で本ファイルへ復元される側のメタデータ。
  private static let pendingMetadataFileName = "memory.memorymetadata.2"
  /// これがあると、azooKey は書き込みが中断されたとみなして復元から始める。
  private static let pauseFileName = ".pause"
  private static let shardPrefix = "memory"
  /// `.2` は azooKey が書き込み中に使う影ファイル。番号付きシャードには両方ある。
  private static let shardSuffixes = [".loudstxt3", ".loudstxt3.2"]

  /// 現世代に属さない `memoryN.loudstxt3` を落とす。
  ///
  /// 守りたいのは **「マージが走っていないとき、置き場は整合している」** という一点。
  /// マージはどれも世代の書き直しなので、走るたびに次の取り残しを置いていく。だから
  /// 「マージの前に呼ぶ」では足りず、**マージの後にも呼ぶ**必要がある。
  ///
  /// 前だけで足りるかどうかは「マージの入口を全部知っているか」に懸かるが、それは
  /// 一度取りこぼしている(保存だけを見ていて、中断からの復元マージを見落とした)。
  /// 入口の数え上げに頼らない形にしてあるので、戻さないこと。呼んでいる場所は
  /// `Converter` に集約されている。
  ///
  /// 何度呼んでも同じ結果になる。掃除するものが無ければ何もしない。
  static func removeStaleShards(in directoryURL: URL) {
    let shardCount: Int
    switch self.generation(in: directoryURL) {
    case .current(let count):
      shardCount = count
    case .orphanedShards:
      // 1 枚も残さない。理由は `Generation.orphanedShards` を参照。
      shardCount = 0
    case .unknown:
      return
    }

    let fileManager = FileManager.default
    guard let names = try? fileManager.contentsOfDirectory(atPath: directoryURL.path) else {
      return
    }

    var removedCount = 0
    for name in names {
      guard let index = self.shardIndex(ofFileNamed: name), index >= shardCount else {
        continue
      }
      do {
        try fileManager.removeItem(at: directoryURL.appending(path: name))
        removedCount += 1
      } catch {
        Log.memory.error(
          "failed to remove a stale learning memory shard: \(error, privacy: .public)")
      }
    }

    if removedCount > 0 {
      Log.memory.info(
        "removed \(removedCount, privacy: .public) stale learning memory shard file(s); the current generation has \(shardCount, privacy: .public)"
      )
    }
  }

  /// 置き場から読み取れた世代の状態。
  private enum Generation {
    /// 現世代のシャード数が分かっている。これより後ろの番号が取り残し。
    case current(shardCount: Int)

    /// メタデータが失われていて、残っているシャードはもう誰にも使えない。
    ///
    /// azooKey は欠けたメタデータを 4 byte のゼロで代用するため、エントリ数は 0 と
    /// 読まれる。それでもマージは最低 1 枚シャードを読みにいくので、`memory0.loudstxt3`
    /// が残っていると 4 byte しかない代用メタデータの先を読んで **プロセスごと落ちる**。
    /// つまりこの状態は、放置すれば保存のたびに死ぬ状態そのもの。
    ///
    /// この状態は正規の書き込み手順からは生まれない(手順の途中では必ず `.pause` が
    /// あり、そちらは `.unknown` に倒す)。生まれるのは学習データのリセットが途中で
    /// 失敗したとき — azooKey の `reset` はファイルを順不同で消し、1 つでも失敗すると
    /// そこで中断するため、メタデータだけ消えてシャードが残ることがある。
    ///
    /// だから取るべき道は「どれが取り残しか推測する」ではなく「**中断されたリセットを
    /// 最後までやる**」。シャードを落とせば、次のマージが空から世代を書き直して復旧する。
    case orphanedShards

    /// 判断がつかない。何も消さない。
    case unknown
  }

  /// いま置き場にあるべきシャードの数。数え上げられなければ `nil`。
  ///
  /// - Note: `internal` なのは、azooKey が実際に書いた置き場と突き合わせるテスト
  ///   (`agreesWithLayoutWrittenByAzooKey`)のため。ヘッダの並びは公開 API ではなく、
  ///   合成したデータを同じ方式で読み返すだけのテストでは形式変更を検知できない。
  static func currentShardCount(in directoryURL: URL) -> Int? {
    guard case .current(let shardCount) = self.generation(in: directoryURL) else {
      return nil
    }
    return shardCount
  }

  /// 置き場を読んで世代の状態を決める。
  ///
  /// どちらのメタデータが正かは `.pause` で決まる。`.pause` があるとき、azooKey は
  /// マージの冒頭で `.2` を本ファイルへ復元してから読み進める。つまりそのとき正なのは
  /// `.2` 側の保留中の世代であって、本ファイルのメタデータは中断前の古い世代を
  /// 指したままのことがある。それで数えると、保留中の世代の末尾シャードを取り残しと
  /// 誤認して消してしまう。
  ///
  /// **`.unknown` は「分からない」であって「0 個」ではない。** 数え上げに使う値のどれか
  /// 一つでも辻褄が合わなければ `.unknown` に倒すこと。消し損ねてもクラッシュするだけだが、
  /// 消しすぎれば利用者の学習は戻らない。全部消してよいのは、残しても誰も読めないと
  /// 確信できる `.orphanedShards` のときだけ。
  private static func generation(in directoryURL: URL) -> Generation {
    let fileManager = FileManager.default
    let isRecovering = fileManager.fileExists(
      atPath: directoryURL.appending(path: Self.pauseFileName).path)
    let metadataFileName = isRecovering ? Self.pendingMetadataFileName : Self.metadataFileName

    guard fileManager.fileExists(atPath: directoryURL.appending(path: metadataFileName).path)
    else {
      // 復元中なら本ファイルのメタデータはまだ生きているかもしれないので触らない。
      return isRecovering ? .unknown : .orphanedShards
    }

    // azooKey は根ノード 2 つを必ず含めて書くので、正しく書かれたヘッダが 0 になることはない。
    let entriesPerShard = DictionaryBuilder.entriesPerShard
    guard let entryCount = self.entryCount(in: directoryURL, fileName: metadataFileName),
      entryCount > 0, entriesPerShard > 0
    else {
      return .unknown
    }

    // 分割幅は「いまリンクしている azooKey の定数」でしかない。置き場を書いたのは
    // 前回動いていたビルドなので、依存を上げて `shardShift` が変わっていれば食い違う。
    // その食い違いに気づかず数えると、まだ現役のシャードを取り残しと誤認して消す
    // (しかも `Converter.init` で、利用者が一文字も打たないうちに)。
    //
    // 置き場がどの幅で書かれたかは、置き場自身が知っている。シャードの先頭 2 byte は
    // そのシャードに入っているエントリ数で、先頭シャードは必ず
    // `min(entryCount, entriesPerShard)` 件まで詰まっている。ここが合わなければ、
    // この版とは違う幅で書かれた置き場ということなので、手を出さない。
    let expectedLeadingCount = min(entryCount, entriesPerShard)
    guard
      self.leadingShardEntryCount(in: directoryURL, isRecovering: isRecovering)
        == expectedLeadingCount
    else {
      return .unknown
    }

    // エントリは先頭から順に詰められるので切り上げでよい。
    return .current(shardCount: (entryCount + entriesPerShard - 1) / entriesPerShard)
  }

  /// 先頭シャードに入っているエントリ数。先頭 2 byte のリトルエンディアン `UInt16`。
  ///
  /// 復元中は `.2` 側が正なので、そちらの先頭シャードを見る。
  private static func leadingShardEntryCount(in directoryURL: URL, isRecovering: Bool) -> Int? {
    let fileName =
      isRecovering ? "\(Self.shardPrefix)0.loudstxt3.2" : "\(Self.shardPrefix)0.loudstxt3"
    guard let data = try? Data(contentsOf: directoryURL.appending(path: fileName)),
      data.count >= 2
    else {
      return nil
    }
    let low = UInt16(data[data.startIndex])
    let high = UInt16(data[data.startIndex + 1])
    return Int(low | (high << 8))
  }

  /// メタデータ先頭 4 byte のリトルエンディアン `UInt32`。
  private static func entryCount(in directoryURL: URL, fileName: String) -> Int? {
    let url = directoryURL.appending(path: fileName)
    guard let data = try? Data(contentsOf: url), data.count >= 4 else {
      return nil
    }
    var value: UInt32 = 0
    for byte in data.prefix(4).reversed() {
      value = (value << 8) | UInt32(byte)
    }
    return Int(value)
  }

  /// `memory12.loudstxt3` や `memory12.loudstxt3.2` から `12` を取り出す。
  ///
  /// 番号を持たない `memory.louds` や `memory.memorymetadata` は現世代の一部なので、
  /// ここで弾いて対象外にする。
  private static func shardIndex(ofFileNamed name: String) -> Int? {
    guard name.hasPrefix(Self.shardPrefix) else {
      return nil
    }
    var digits = name.dropFirst(Self.shardPrefix.count)
    guard let suffix = Self.shardSuffixes.first(where: { digits.hasSuffix($0) }) else {
      return nil
    }
    digits = digits.dropLast(suffix.count)
    // `Int(_:)` は符号を受け付けるため、10 進数字だけであることを先に確かめる。
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      return nil
    }
    return Int(digits)
  }
}
