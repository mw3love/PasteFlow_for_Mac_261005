import Foundation

/// 순차 붙여넣기 큐. 복사한 순서대로 쌓고, 붙여넣을 때마다 포인터를 하나씩 민다.
///
/// 새 묶음 시작(큐 비우고 다시 쌓기) 조건 — 윈도우판과 동일:
/// 1. 붙여넣기가 이미 시작된 뒤(pointer > 0) 새로 복사했을 때
/// 2. 직전 복사로부터 `idleResetSec` 이상 지난 뒤 복사했을 때
/// 일반 ⌘V(`markPlainPaste`)나 소진 완료(`clear`)도 큐를 비운다.
///
/// 키 감시 스레드와 메인 스레드가 함께 부르므로 모든 접근을 잠금으로 보호한다.
public final class PasteQueue {
    public static let defaultIdleResetSec: TimeInterval = 10

    private let lock = NSLock()
    private let clock: () -> Date
    private var _items: [ClipItem] = []
    private var pointer = 0
    private var lastCopyTime: Date?
    private var _idleResetSec: TimeInterval

    public init(idleResetSec: TimeInterval = PasteQueue.defaultIdleResetSec, clock: @escaping () -> Date = Date.init) {
        self._idleResetSec = idleResetSec
        self.clock = clock
    }

    public var idleResetSec: TimeInterval {
        get { lock.withLock { _idleResetSec } }
        set { lock.withLock { _idleResetSec = newValue } }
    }

    public func add(_ item: ClipItem) {
        lock.withLock {
            let now = clock()
            let idleExpired = lastCopyTime.map { now.timeIntervalSince($0) >= _idleResetSec } ?? false
            if pointer > 0 || idleExpired {
                resetUnlocked()
            }
            _items.append(item)
            lastCopyTime = now
        }
    }

    /// 다음 항목을 꺼낸다. 소진됐으면 nil.
    public func next() -> ClipItem? {
        lock.withLock {
            guard pointer < _items.count else { return nil }
            defer { pointer += 1 }
            return _items[pointer]
        }
    }

    public var status: (pointer: Int, total: Int) {
        lock.withLock { (pointer, _items.count) }
    }

    public var isExhausted: Bool {
        lock.withLock { pointer >= _items.count }
    }

    public var items: [ClipItem] {
        lock.withLock { _items }
    }

    /// 일반 ⌘V(물리 키) — 큐를 비운다.
    public func markPlainPaste() { clear() }

    public func clear() {
        lock.withLock { resetUnlocked() }
    }

    /// 히스토리에서 지운 항목을 큐에서도 뺀다. 이미 지나간 항목이면 포인터도 당긴다.
    @discardableResult
    public func remove(id: Int64) -> Bool {
        lock.withLock {
            guard let i = _items.firstIndex(where: { $0.id == id }) else { return false }
            _items.remove(at: i)
            if i < pointer { pointer -= 1 }
            return true
        }
    }

    private func resetUnlocked() {
        _items.removeAll()
        pointer = 0
    }
}
