import Testing

@testable import KotoCore

/// 「入れ替えたら前のものは取り消される」ことについての回帰テスト。
///
/// 取りこぼすと、学習データの保存で古い予約が生き残り、待っているはずの保存が早く走る。
/// その取りこぼしは実時間を絡めないと見えないので、型の側で見えるようにしてある。

@Test("差し替えると前のタスクは取り消される")
@MainActor
func replacingCancelsThePreviousTask() {
  var slot = ExclusiveTask()
  let first = Task<Void, Never> {}
  let second = Task<Void, Never> {}

  slot.replace(with: first)
  slot.replace(with: second)

  #expect(first.isCancelled)
  #expect(!second.isCancelled)
  #expect(slot.isScheduled)
}

@Test("取り消すと抱えているタスクも取り消され、予約は無くなる")
@MainActor
func cancellingClearsTheSlot() {
  var slot = ExclusiveTask()
  let task = Task<Void, Never> {}
  slot.replace(with: task)

  slot.cancel()

  #expect(task.isCancelled)
  #expect(!slot.isScheduled)
}

@Test("clear は取り消さずに手放す")
@MainActor
func clearReleasesWithoutCancelling() {
  var slot = ExclusiveTask()
  let task = Task<Void, Never> {}
  slot.replace(with: task)

  // 走り切ったタスク自身が後片付けをする経路。ここで取り消すと自分を取り消すことになる。
  slot.clear()

  #expect(!task.isCancelled)
  #expect(!slot.isScheduled)
}

@Test("何も抱えていなければ予約は無い")
@MainActor
func emptySlotIsNotScheduled() {
  var slot = ExclusiveTask()

  #expect(!slot.isScheduled)

  slot.cancel()

  #expect(!slot.isScheduled)
}
