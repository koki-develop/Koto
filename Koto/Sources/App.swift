//
//  App.swift
//  Koto
//
//  Created by koki sato on 2024/09/15.
//

import InputMethodKit
import KotoCore
import os

class NSManualApplication: NSApplication {
  let appDelegate = AppDelegate()

  override init() {
    super.init()
    self.delegate = self.appDelegate
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  // IMKServer は入力メソッドにつき 1 つだけ生成する(IMKServer.h に
  // "An input method should create one and only one of these objects" と明記されている)。
  // 生成は applicationDidFinishLaunching で一度だけ行う。
  var server: IMKServer?

  private var terminationSignalSource: DispatchSourceSignal?

  func applicationDidFinishLaunching(_ notification: Notification) {
    self.server = IMKServer(
      name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
      bundleIdentifier: Bundle.main.bundleIdentifier
    )
    self.installTerminationSignalHandler()

    // 辞書の読み込みは同期 I/O を伴う。ここで済ませておかないと、最初の
    // アプリ切り替え(= フォーカス遷移の真っ最中)に読み込むことになる。
    MainActor.assumeIsolated {
      KotoInputController.preload()
    }
  }

  // 学習データの保存は入力が落ち着いてからまとめて行っているため、
  // 終了時に保存待ちが残っていることがある。ここで書き出す。
  func applicationWillTerminate(_ notification: Notification) {
    MainActor.assumeIsolated {
      KotoInputController.flushLearningData()
    }
  }

  /// メインスレッドの後始末をこれだけ待って、終わらなければ諦めて落ちる。
  ///
  /// 学習データの保存は学習量に比例して伸びるため、短すぎると学習を貯めた利用者ほど
  /// 毎回打ち切られる。正常時はこの待ち時間を使い切らずに抜けるので、効いてくるのは
  /// メインスレッドが詰まっているときだけ。長めに取っておく。
  private static let flushTimeout: DispatchTimeInterval = .seconds(2)

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "me.koki.inputmethod.Koto", category: "lifecycle")

  // SIGTERM では applicationWillTerminate が呼ばれないため、こちらで拾う。
  //
  // 気をつけるのは、SIGTERM を握った時点で既定動作(即時終了)を失うこと。
  // 入力メソッドはクライアントへの同期呼び出しでメインスレッドが止まりうる
  // (Client.swift 参照)ので、素直にメインキューで拾うと、止まっている間の
  // SIGTERM が一切効かなくなり SIGKILL でしか落とせなくなる。
  // 固まった入力メソッドを落とせないのは、後始末を取りこぼすより悪い。
  //
  // そのため、
  //   - シグナルはバックグラウンドキューで拾う(メインが詰まっていても必ず走る)
  //   - まず番人を仕掛けてから、メインへ後始末を投げる
  //   - 後始末が間に合わなければ番人が落とす
  // という形にする。
  private func installTerminationSignalHandler() {
    let source = DispatchSource.makeSignalSource(
      signal: SIGTERM, queue: .global(qos: .userInitiated))
    source.setEventHandler {
      // メインが詰まっていたときの保険。先に仕掛けておく。
      DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.flushTimeout) {
        // 保存を打ち切って落ちる。書き込み途中でも次回の変換時に azooKey 側が
        // 検出して巻き戻すが、今回ぶんの学習は失われるので記録を残す。
        Self.log.error("SIGTERM: flush did not finish in time; exiting without saving")
        _exit(0)
      }
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          KotoInputController.flushLearningData()
        }
        exit(0)
      }
    }
    source.resume()
    self.terminationSignalSource = source

    // 既定動作を止めるのは、シグナルを拾える状態になってから。逆にすると、
    // その間に届いた SIGTERM が握り潰されて誰にも届かなくなる(シグナルソースは
    // 登録前に届いたぶんを後から配送しない)。この順序なら取りこぼすのは後始末だけで、
    // しかも起動直後は保存待ちが無いので失うものが無い。
    signal(SIGTERM, SIG_IGN)
  }
}
