import Foundation

/// 패널에서 항목을 골라 큐를 지정할 때(C)의 순서 — 윈도우판 `_on_queue_select`와 같다.
public enum QueueSelection {
    /// - history: 최신 먼저(패널에 보이는 순서). 고른 항목부터 최신 쪽으로 → [고른 것, …, 최신].
    /// - pinned: 고정 순서. 고른 항목부터 첫 고정 쪽으로 거꾸로 → [고른 것, …, 첫 고정].
    /// 목록에 없으면 nil.
    public static func ids(for id: Int64, history: [Int64], pinned: [Int64]) -> [Int64]? {
        if let i = history.firstIndex(of: id) { return Array(history[0...i].reversed()) }
        if let i = pinned.firstIndex(of: id) { return Array(pinned[0...i].reversed()) }
        return nil
    }
}

/// 고정 항목을 끌어 순서를 바꿀 때의 새 순서.
public enum PinOrder {
    /// `id`를 `target` 바로 앞으로 옮긴다(`target`이 nil이면 맨 뒤). 목록에 없던 id는 그 자리에 끼운다.
    public static func moving(_ id: Int64, before target: Int64?, in order: [Int64]) -> [Int64] {
        guard id != target else { return order }
        var result = order.filter { $0 != id }
        if let target, let i = result.firstIndex(of: target) { result.insert(id, at: i) } else { result.append(id) }
        return result
    }
}
