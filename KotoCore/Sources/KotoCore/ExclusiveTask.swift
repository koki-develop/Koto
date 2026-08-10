//
//  ExclusiveTask.swift
//  Koto
//

/// 常に 1 本だけ生かしておくタスクの置き場。
///
/// 「入れ替えるときは前のものを取り消す」を呼び出し側のお作法にすると、どこか 1 か所で
/// 忘れたときに古い予約が生き残る。学習データの保存でそれが起きると、待っているはずの
/// 保存が早く走り、待ち時間の意味が無くなる。しかもその取りこぼしは、実時間を絡めない
/// かぎりテストから見えない。忘れようがない形にしておく。
struct ExclusiveTask {
  private var task: Task<Void, Never>?

  /// 走る予定のタスクを抱えているか。
  var isScheduled: Bool {
    return self.task != nil
  }

  /// 新しいタスクに差し替える。前のタスクは取り消される。
  mutating func replace(with task: Task<Void, Never>) {
    self.task?.cancel()
    self.task = task
  }

  /// 抱えているタスクを取り消して手放す。
  mutating func cancel() {
    self.task?.cancel()
    self.task = nil
  }

  /// 参照だけ手放す。走り切ったタスク自身が後片付けをするときに使う。
  mutating func clear() {
    self.task = nil
  }
}
