//
//  CandidateWindowController.swift
//  Koto
//

import AppKit

@MainActor
protocol CandidateWindowDelegate: AnyObject {
  func candidateWindow(_ window: CandidateWindowController, didClickCandidateAt index: Int)
  /// ホイール操作でリストがスクロールされた。`rows` は正で下方向。
  func candidateWindow(_ window: CandidateWindowController, didScrollBy rows: Int)
}

/// 候補ウィンドウ(パネル)の生成・表示・配置を担う。
///
/// 候補列そのものは `KotoInputController` が単一の情報源として保持し、
/// このクラスは渡された `CandidateList` を描画してマウス操作を差し戻すだけに徹する。
@MainActor
final class CandidateWindowController {
  /// カーソル矩形の高さが取れないアプリ向けの既定行高。
  private static let fallbackCursorHeight: CGFloat = 16
  private static let cornerRadius: CGFloat = 8
  /// ウィンドウ幅の上限を作業領域から求めるときに左右へ残す余白。
  private static let screenMargin: CGFloat = 8
  /// スクリーン情報が得られない場合に作業領域の幅の代わりに使う値。
  private static let fallbackScreenWidth: CGFloat = 480

  private let panel: NSPanel
  private let listView = CandidateListView()

  weak var delegate: (any CandidateWindowDelegate)?

  init() {
    let backgroundView = NSVisualEffectView()
    backgroundView.material = .menu
    backgroundView.blendingMode = .behindWindow
    backgroundView.state = .active

    let contentView = NSView()
    contentView.addSubview(backgroundView)
    contentView.addSubview(self.listView)

    for view in [contentView, backgroundView] {
      // NSVisualEffectView の behind-window ブレンドはウィンドウサーバ側で行われ、
      // 親レイヤのマスクが効かないことがあるため、角丸は両方に設定する。
      view.wantsLayer = true
      view.layer?.cornerRadius = Self.cornerRadius
      view.layer?.masksToBounds = true
    }

    for view in [backgroundView, self.listView] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        view.topAnchor.constraint(equalTo: contentView.topAnchor),
        view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      ])
    }

    // .nonactivatingPanel により、クリックしても入力メソッドのプロセスが
    // アクティブにならず、フォアグラウンドアプリからフォーカスを奪わない。
    self.panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true)
    self.panel.contentView = contentView
    self.panel.isFloatingPanel = true
    self.panel.level = .popUpMenu
    // ホストアプリがモーダルシートを出していても候補を表示できるようにする。
    self.panel.worksWhenModal = true
    self.panel.hidesOnDeactivate = false
    self.panel.isMovable = false
    self.panel.isMovableByWindowBackground = false
    self.panel.isOpaque = false
    self.panel.backgroundColor = .clear
    self.panel.hasShadow = true
    self.panel.isReleasedWhenClosed = false
    // ホバー強調のため、キーウィンドウでなくてもマウス移動イベントを受け取る。
    self.panel.acceptsMouseMovedEvents = true
    self.panel.collectionBehavior = [
      .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
    ]

    self.listView.delegate = self
  }

  /// 候補ウィンドウを `cursorRect` の近傍に表示する。
  ///
  /// `cursorRect` はクライアントから得た未確定文字列先頭のスクリーン座標。
  func show(_ list: CandidateList, at cursorRect: NSRect, delegate: any CandidateWindowDelegate) {
    self.delegate = delegate

    guard !list.isEmpty else {
      self.hideNow()
      return
    }

    // 別の候補列を出し直すので、ホバーやホイールの端数など前回の持ち越しは捨てる。
    self.listView.clear()
    self.listView.update(list)

    let anchor = Self.anchorRect(from: cursorRect)
    // 表示先のスクリーンを先に決め、その作業領域からウィンドウ幅の上限を導く。
    // 画面に収まる限りは長い候補も省略せずに見せ、はみ出す場合だけ切り詰める。
    let visibleFrame =
      CandidateWindowPositioning.screen(containing: anchor.origin)?.visibleFrame
      ?? NSScreen.main?.visibleFrame
    let maxWidth = (visibleFrame?.width ?? Self.fallbackScreenWidth) - Self.screenMargin * 2
    let size = self.listView.desiredSize(maxWidth: maxWidth)

    if let visibleFrame {
      let frame = CandidateWindowPositioning.frame(below: anchor, size: size, within: visibleFrame)
      self.panel.setFrame(frame, display: true)
    } else {
      self.panel.setContentSize(size)
    }

    self.panel.orderFront(nil)
    // 角丸に沿った影を引き直す。setFrame だけでは古い形状が残る。
    self.panel.invalidateShadow()
    // ホバー行はウィンドウの位置が決まってからでないと求まらない。
    self.listView.refreshHover()
  }

  /// `delegate` の候補列を表示中かどうか。
  ///
  /// ウィンドウはプロセス全体で共有していて、別クライアントのコントローラが
  /// 引き取っていることがある。表示を前提にした操作の前にこれで確かめること。
  func isShowing(for delegate: any CandidateWindowDelegate) -> Bool {
    return self.panel.isVisible && self.delegate === delegate
  }

  /// 入力セッションの切り替えにあわせてウィンドウを引き取り、いったん畳む。
  ///
  /// アクティブな入力セッションは常に 1 つなので、`activateServer` を受けた
  /// コントローラが無条件に持ち主になる。「誰が閉じたいか」ではなく
  /// 「今どのセッションがアクティブか」で表示を決めるのが要点で、これにより
  /// 前の持ち主が `deactivateServer` を受け取れないまま放置されても、
  /// パネルが最前面に残り続けることがない。
  ///
  /// 引き取った側が変換中だった場合の再表示は、クライアントへの問い合わせを
  /// 伴うため、次のキー入力時(`handle` の冒頭)まで遅らせる。
  func takeOver(by owner: any CandidateWindowDelegate) {
    self.hideNow()
    self.delegate = owner
  }

  /// 表示中のウィンドウの中身だけを差し替える。
  ///
  /// 選択位置の移動やスクロールではウィンドウの位置・サイズは変わらないため、
  /// クライアントへのカーソル位置問い合わせを伴わないこちらを使う。
  /// 呼び出し前に `isShowing(for:)` が真であることを確かめること。
  func update(_ list: CandidateList) {
    guard self.panel.isVisible else {
      return
    }
    guard !list.isEmpty else {
      self.hideNow()
      return
    }
    self.listView.update(list)
  }

  /// 自分が出した候補ウィンドウを閉じる。持ち主でなければ何もしない。
  ///
  /// IMK は `deactivateServer` と `activateServer` の到着順を保証しないため、
  /// 遅れて届いた別クライアントの後始末が、いま使われているウィンドウを
  /// 畳んでしまうのを防ぐ。持ち主の付け替えは `takeOver(by:)` が担う。
  func hide(requestedBy owner: any CandidateWindowDelegate) {
    guard self.delegate === owner else {
      return
    }
    self.hideNow()
  }

  private func hideNow() {
    self.delegate = nil
    self.listView.clear()
    guard self.panel.isVisible else {
      return
    }
    self.panel.orderOut(nil)
  }

  /// クライアントから得たカーソル矩形を、配置計算に使える形に整える。
  ///
  /// カーソル位置を返さないアプリがあるため、使えない値ならポインタ位置を
  /// 代わりの基準にする(画面左下隅に貼り付くよりは実際の入力位置に近い)。
  private static func anchorRect(from cursorRect: NSRect) -> NSRect {
    var rect = cursorRect
    if !rect.origin.x.isFinite || !rect.origin.y.isFinite
      || (rect.isEmpty && rect.origin == .zero)
    {
      rect = NSRect(origin: NSEvent.mouseLocation, size: .zero)
    }
    // 行の高さを返さないアプリ向けに、得られた点を行の下端とみなして上へ補う。
    // 補った高さはウィンドウを上側へ反転させるときの退避量になる。
    if !rect.height.isFinite || rect.height <= 0 {
      rect.size.height = Self.fallbackCursorHeight
    }
    if !rect.width.isFinite || rect.width < 0 {
      rect.size.width = 0
    }
    return rect
  }
}

extension CandidateWindowController: CandidateListViewDelegate {
  func candidateListView(_ view: CandidateListView, didClickCandidateAt index: Int) {
    self.delegate?.candidateWindow(self, didClickCandidateAt: index)
  }

  func candidateListView(_ view: CandidateListView, didScrollBy rows: Int) {
    self.delegate?.candidateWindow(self, didScrollBy: rows)
  }
}
