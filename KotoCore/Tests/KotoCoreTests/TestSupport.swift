import AppKit
import Foundation
import KanaKanjiConverterModule

@testable import KotoCore

/// このテスト実行ぶんの一時ディレクトリをまとめる親。
///
/// パスをプロセス ID から決め打ちにしてあるのは、`atexit` に渡すクロージャが
/// 何も捕捉できない(C 関数ポインタに変換される)ため。
private func testRootPath() -> String {
  return NSTemporaryDirectory() + "koto-tests-\(ProcessInfo.processInfo.processIdentifier)"
}

private let testRootURL: URL = {
  let url = URL(fileURLWithPath: testRootPath(), isDirectory: true)
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  // 変換は学習メモリのファイルを作るため、放っておくと実行のたびに溜まっていく。
  atexit {
    try? FileManager.default.removeItem(atPath: testRootPath())
  }
  return url
}()

/// 実行ごとに作り捨てるディレクトリ。テスト終了時に親ごと消える。
func throwawayDirectoryURL() -> URL {
  let directoryURL = testRootURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  return directoryURL
}

/// 捨てて良いディレクトリを向いた `Converter`。
///
/// 待ち時間の既定はテスト中に保存が発火しない長さ。保存のタイミングそのものを
/// 見るテストだけが、**すべての**待ち時間を明示して上書きすること。
@MainActor
func makeThrowawayConverter(
  directoryURL: URL = throwawayDirectoryURL(),
  saveDelay: Duration = .seconds(600),
  maxSaveDelay: Duration = .seconds(600)
) -> Converter {
  return Converter(
    convertOptions: throwawayOptions(directoryURL: directoryURL),
    saveDelay: saveDelay,
    maxSaveDelay: maxSaveDelay
  )
}

/// テスト用のコントローラ。
///
/// **変換器の差し替えを省かないこと。** 既定の共有 `Converter` は
/// `~/Library/Application Support/Koto` を読み書きするので、省くと開発者の
/// 実際の学習データを壊し、しかもテストは何も言わずに通る。
@MainActor
func makeController() -> KotoInputController {
  let controller = KotoInputController(server: nil, delegate: nil, client: nil)!
  controller.converter = makeThrowawayConverter()
  return controller
}

/// 候補を選んでいる状態(`.selecting`)のコントローラを組み立てる。
///
/// 候補ウィンドウも実際に開いておく。開いていないと `handle` の入口の
/// `syncCandidateWindow` がカーソル位置を取り直しにいくため、
/// 実際の `.selecting` とはクライアント呼び出しの回数が変わってしまう。
@MainActor
func makeSelectingController(
  composing: String, candidateText: String, surfaceCount: Int
) -> KotoInputController {
  let controller = makeController()
  controller.composingText.append(composing, inputStyle: .direct)
  controller.candidateList.replace(with: [makeCandidate(candidateText, surfaceCount: surfaceCount)])
  controller.state = .selecting
  controller.candidateWindow.show(controller.candidateList, at: .zero, delegate: controller)
  return controller
}

func makeCandidate(_ text: String, surfaceCount: Int, isLearningTarget: Bool = true) -> Candidate {
  return Candidate(
    text: text,
    value: 0,
    composingCount: .surfaceCount(surfaceCount),
    lastMid: 0,
    data: [],
    isLearningTarget: isLearningTarget
  )
}

func makeKeyEvent(
  characters: String, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = []
) -> NSEvent {
  return NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: modifierFlags,
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: characters,
    charactersIgnoringModifiers: characters,
    isARepeat: false,
    keyCode: keyCode
  )!
}

/// `condition` が真になるまで待つ。`timeout` を過ぎても真にならなければ `false`。
///
/// 保存がいつ発火するかを見るテストは、実時間だけでなく MainActor の空き具合にも
/// 左右される。swift-testing はテストを並列に走らせるので、他の `@MainActor` テストが
/// 握っている間は保存のタスクが順番待ちになる。上限を待ち時間の実測で決め打ちにすると
/// そこで落ちる。
///
/// 「まだ保存されていないこと」(下限)は待つ前に別途見ているので、上限は緩くてよい。
/// 締切が延びる回帰であれば、どれだけ緩くしても真にならない。
@MainActor
func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
  let deadline = ContinuousClock.now.advanced(by: timeout)
  while ContinuousClock.now < deadline {
    if condition() {
      return true
    }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return condition()
}

/// 製品コードと同じ変換オプション。ただし学習データとユーザ辞書の置き場は
/// 捨てて良いディレクトリに向ける。既定のままだと変換が
/// `~/Library/Application Support/Koto` を読み書きしてしまい、
/// 実際の学習内容でテスト結果が変わるうえ、利用者の学習データを壊す。
func throwawayOptions(directoryURL: URL = throwawayDirectoryURL()) -> ConvertRequestOptions {
  return options(memoryDirectoryURL: directoryURL, sharedContainerURL: directoryURL)
}
