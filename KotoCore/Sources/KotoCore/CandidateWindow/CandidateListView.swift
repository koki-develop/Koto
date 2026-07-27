//
//  CandidateListView.swift
//  Koto
//

import AppKit

@MainActor
protocol CandidateListViewDelegate: AnyObject {
  func candidateListView(_ view: CandidateListView, didClickCandidateAt index: Int)
  /// ホイール操作でリストがスクロールされた。`rows` は正で下方向。
  func candidateListView(_ view: CandidateListView, didScrollBy rows: Int)
}

/// 候補リストの描画とマウス操作を担うビュー。
///
/// スクロールを `NSScrollView` ではなくモデル(`CandidateList.visibleRange`)側の
/// 表示範囲で表現しているため、描画される行と数字キーの割り当てが同じ範囲から
/// 導かれる。表示とキー割り当てがずれる余地がなく、スクロールビューまわりの
/// レイアウト・タイミング問題も持ち込まない。
final class CandidateListView: NSView {
  enum Metrics {
    static let rowHeight: CGFloat = 26
    static let verticalPadding: CGFloat = 5
    static let horizontalPadding: CGFloat = 9
    /// 選択・ホバー時のハイライト矩形を行から内側に詰める量。
    static let rowInset: CGFloat = 4
    static let rowCornerRadius: CGFloat = 5
    static let numberColumnWidth: CGFloat = 14
    static let numberSpacing: CGFloat = 6
    static let minTextWidth: CGFloat = 96
    static let scrollBarWidth: CGFloat = 3
    static let scrollBarInset: CGFloat = 3
  }

  private static let candidateFont = NSFont.systemFont(ofSize: 15)
  private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

  weak var delegate: (any CandidateListViewDelegate)?

  private var list = CandidateList()
  private var hoveredIndex: Int?
  private var pressedIndex: Int?
  private var scrollAccumulator = ScrollAccumulator()
  private var trackingArea: NSTrackingArea?

  override var isFlipped: Bool { true }

  // アプリが非アクティブなままクリックを受け取るために必要。
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  func update(_ list: CandidateList) {
    self.list = list
    self.pressedIndex = nil
    self.refreshHover()
    self.needsDisplay = true
  }

  /// ポインタの現在位置からホバー行を取り直す。
  ///
  /// 位置をキャッシュせずその場で問い合わせるのは、ウィンドウを動かした直後でも
  /// 正しい行を出すため。キャッシュした座標はウィンドウ移動で無効になる。
  /// 呼び出し側はウィンドウの位置・サイズを確定させてからこれを呼ぶこと。
  func refreshHover() {
    guard let window = self.window, window.isVisible else {
      self.setHoveredIndex(nil)
      return
    }
    let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    self.setHoveredIndex(self.candidateIndex(at: point))
  }

  /// 非表示にするときの後片付け。
  func clear() {
    self.list = CandidateList()
    self.hoveredIndex = nil
    self.pressedIndex = nil
    self.scrollAccumulator.reset()
    self.needsDisplay = true
  }

  /// 現在の候補列を過不足なく表示するために必要なサイズ。`maxWidth` を超えない。
  ///
  /// 幅は表示中の行ではなく全候補から求める。スクロールのたびにウィンドウ幅が
  /// 変わると視覚的に落ち着かないため。上限を呼び出し側から受け取るのは、
  /// 画面幅に収まる限り長い候補も省略せずに見せたいから。
  func desiredSize(maxWidth: CGFloat) -> NSSize {
    let rows = self.list.visibleRange.count
    guard rows > 0 else {
      return NSSize(width: 1, height: 1)
    }

    let chrome = self.chromeWidth(of: self.list)
    let availableForText = max(maxWidth - chrome, Metrics.minTextWidth)
    let width = chrome + min(self.textColumnWidth(of: self.list), availableForText)
    let height = Metrics.verticalPadding * 2 + CGFloat(rows) * Metrics.rowHeight
    return NSSize(width: ceil(width), height: ceil(height))
  }

  // MARK: - 描画

  override func draw(_ dirtyRect: NSRect) {
    let range = self.list.visibleRange
    guard !range.isEmpty else {
      return
    }

    let textOriginX =
      Metrics.horizontalPadding + Metrics.numberColumnWidth + Metrics.numberSpacing
    let textTrailing = Metrics.horizontalPadding + self.scrollBarSpace(of: self.list)
    let textWidth = max(self.bounds.width - textOriginX - textTrailing, 0)

    for (row, index) in range.enumerated() {
      let rect = self.rowRect(forDisplayedRow: row)
      guard rect.intersects(dirtyRect) else {
        continue
      }

      let isSelected = index == self.list.selectedIndex
      if isSelected {
        NSColor.selectedContentBackgroundColor.setFill()
        self.highlightPath(in: rect).fill()
      } else if index == self.hoveredIndex {
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        self.highlightPath(in: rect).fill()
      }

      self.draw(
        text: "\(row + 1).",
        font: Self.numberFont,
        color: isSelected
          ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.7)
          : NSColor.tertiaryLabelColor,
        alignment: .right,
        in: NSRect(
          x: Metrics.horizontalPadding, y: rect.minY,
          width: Metrics.numberColumnWidth, height: rect.height))

      self.draw(
        text: self.list.candidates[index].text,
        font: Self.candidateFont,
        color: isSelected ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor,
        alignment: .left,
        in: NSRect(x: textOriginX, y: rect.minY, width: textWidth, height: rect.height))
    }

    self.drawScrollBar()
  }

  private func draw(
    text: String,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment,
    in rect: NSRect
  ) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byTruncatingTail

    let string = NSAttributedString(
      string: text,
      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let height = string.size().height
    let origin = NSPoint(x: rect.minX, y: rect.minY + (rect.height - height) / 2)
    string.draw(
      with: NSRect(origin: origin, size: NSSize(width: rect.width, height: height)),
      options: [.usesLineFragmentOrigin])
  }

  private func drawScrollBar() {
    guard self.list.isScrollable else {
      return
    }

    let track = NSRect(
      x: self.bounds.maxX - Metrics.scrollBarInset - Metrics.scrollBarWidth,
      y: Metrics.verticalPadding,
      width: Metrics.scrollBarWidth,
      height: self.bounds.height - Metrics.verticalPadding * 2)
    guard track.height > 0 else {
      return
    }

    let visibleRatio = CGFloat(CandidateList.pageSize) / CGFloat(self.list.count)
    let thumbHeight = max(track.height * visibleRatio, Metrics.scrollBarWidth * 3)
    let maxStart = CGFloat(self.list.count - CandidateList.pageSize)
    let progress = maxStart > 0 ? CGFloat(self.list.visibleStart) / maxStart : 0
    let thumb = NSRect(
      x: track.minX,
      y: track.minY + (track.height - thumbHeight) * progress,
      width: track.width,
      height: thumbHeight)

    NSColor.labelColor.withAlphaComponent(0.1).setFill()
    NSBezierPath(roundedRect: track, xRadius: track.width / 2, yRadius: track.width / 2).fill()
    NSColor.labelColor.withAlphaComponent(0.35).setFill()
    NSBezierPath(roundedRect: thumb, xRadius: thumb.width / 2, yRadius: thumb.width / 2).fill()
  }

  private func highlightPath(in rect: NSRect) -> NSBezierPath {
    // スクロールバーの下に潜り込まないよう、右側はその分だけ手前で止める。
    var rect = rect
    rect.size.width -= self.scrollBarSpace(of: self.list)
    return NSBezierPath(
      roundedRect: rect.insetBy(dx: Metrics.rowInset, dy: 1),
      xRadius: Metrics.rowCornerRadius,
      yRadius: Metrics.rowCornerRadius)
  }

  // MARK: - レイアウト計算

  private func rowRect(forDisplayedRow row: Int) -> NSRect {
    return NSRect(
      x: 0,
      y: Metrics.verticalPadding + CGFloat(row) * Metrics.rowHeight,
      width: self.bounds.width,
      height: Metrics.rowHeight)
  }

  /// 候補テキスト以外(余白・番号欄・スクロールバー)が占める幅。
  private func chromeWidth(of list: CandidateList) -> CGFloat {
    return Metrics.horizontalPadding * 2
      + Metrics.numberColumnWidth
      + Metrics.numberSpacing
      + self.scrollBarSpace(of: list)
  }

  /// 全候補のうち最も広いものの幅。
  ///
  /// 変換結果は数十〜数百件届くため、全件をレイアウトすると変換処理そのものより重くなる
  /// (実測で「かんじ」363 件・約 2.8ms、変換自体は約 1.4ms)。
  /// 「文字数 × フォントの最大字送り」が実幅の確実な上限になることを使い、長い順に見て
  /// 上限が既知の最大幅を超えなくなった時点で打ち切る。結果は全件レイアウトと一致する。
  private func textColumnWidth(of list: CandidateList) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: Self.candidateFont]
    let maxAdvance = Self.candidateFont.maximumAdvancement.width
    let byLength = list.candidates.map { ($0.text.count, $0.text) }.sorted { $0.0 > $1.0 }

    var widest = CGFloat.zero
    for (count, text) in byLength {
      guard CGFloat(count) * maxAdvance > widest else {
        break
      }
      widest = max(widest, NSAttributedString(string: text, attributes: attributes).size().width)
    }
    return max(ceil(widest), Metrics.minTextWidth)
  }

  private func scrollBarSpace(of list: CandidateList) -> CGFloat {
    return list.isScrollable ? Metrics.scrollBarWidth + Metrics.scrollBarInset * 2 : 0
  }

  private func candidateIndex(at point: NSPoint) -> Int? {
    // スクロールバーの帯は当たり判定から外す。つまみを掴もうとしたクリックで
    // 候補が確定してしまわないようにするため。
    var hitArea = self.bounds
    hitArea.size.width -= self.scrollBarSpace(of: self.list)
    guard hitArea.contains(point) else {
      return nil
    }
    let range = self.list.visibleRange
    guard !range.isEmpty else {
      return nil
    }

    let offset = point.y - Metrics.verticalPadding
    guard offset >= 0 else {
      return nil
    }
    let row = Int(offset / Metrics.rowHeight)
    guard row < range.count else {
      return nil
    }
    return range.lowerBound + row
  }

  // MARK: - マウス操作

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let trackingArea = self.trackingArea {
      self.removeTrackingArea(trackingArea)
    }
    // 入力メソッドのプロセスは常に非アクティブなため .activeAlways が必須。
    let trackingArea = NSTrackingArea(
      rect: self.bounds,
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
      owner: self)
    self.addTrackingArea(trackingArea)
    self.trackingArea = trackingArea
  }

  override func mouseEntered(with event: NSEvent) {
    self.updateHover(with: event)
  }

  override func mouseMoved(with event: NSEvent) {
    self.updateHover(with: event)
  }

  override func mouseExited(with event: NSEvent) {
    self.setHoveredIndex(nil)
  }

  override func mouseDown(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    self.pressedIndex = self.candidateIndex(at: point)
    self.setHoveredIndex(self.pressedIndex)
  }

  override func mouseDragged(with event: NSEvent) {
    self.updateHover(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    let pressedIndex = self.pressedIndex
    self.pressedIndex = nil

    let point = self.convert(event.locationInWindow, from: nil)
    guard let index = self.candidateIndex(at: point), index == pressedIndex else {
      return
    }
    self.delegate?.candidateListView(self, didClickCandidateAt: index)
  }

  override func scrollWheel(with event: NSEvent) {
    guard self.list.isScrollable else {
      return
    }

    // 精密デルタ(トラックパッド)はピクセル単位で細かく届くため行高で割り、
    // 非精密デルタ(ホイール)はもともと行数なのでそのまま渡す。
    let delta =
      event.hasPreciseScrollingDeltas
      ? event.scrollingDeltaY / Metrics.rowHeight
      : event.scrollingDeltaY
    let rows = self.scrollAccumulator.rows(
      forDelta: delta, isGestureStart: event.phase.contains(.began))

    guard rows != 0 else {
      return
    }
    // scrollingDeltaY は「内容を下へ動かす」向きが正なので、行送りとは符号が逆。
    self.delegate?.candidateListView(self, didScrollBy: -rows)
  }

  private func updateHover(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    self.setHoveredIndex(self.candidateIndex(at: point))
  }

  private func setHoveredIndex(_ index: Int?) {
    guard self.hoveredIndex != index else {
      return
    }
    self.hoveredIndex = index
    self.needsDisplay = true
  }
}
