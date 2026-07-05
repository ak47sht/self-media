import Combine
import Foundation
import MediaLibCore

/// 批量多选的状态容器。
///
/// 仅承载纯选择态（是否处于多选、已选 ID 集合）与其增删操作；批量动作仍留在 AppState extension，
/// 因为它们依赖 repository、Trakt、日志和提示等应用级能力。
@MainActor
final class SelectionStore: ObservableObject {
    @Published private(set) var isSelectionModeActive = false
    @Published private(set) var selectedItemIDs: Set<String> = []

    /// 进入/退出多选模式；退出时清空已选。
    func toggleMode() {
        isSelectionModeActive.toggle()
        if !isSelectionModeActive {
            selectedItemIDs.removeAll()
        }
    }

    /// 退出多选并清空（已是退出且无选中时短路）。
    func exit() {
        guard isSelectionModeActive || !selectedItemIDs.isEmpty else { return }
        isSelectionModeActive = false
        selectedItemIDs.removeAll()
    }

    func toggleItem(_ id: String) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    /// 在给定 ID 范围内全选 / 取消全选。
    func setSelection(_ ids: [String], selected: Bool) {
        if selected {
            selectedItemIDs.formUnion(ids)
        } else {
            selectedItemIDs.subtract(ids)
        }
    }

    /// 由 ID 集合还原为有序条目（按传入顺序），仅取集合内存在的条目。
    func resolveSelected(orderedBy ordered: [MediaItem]) -> [MediaItem] {
        ordered.filter { selectedItemIDs.contains($0.id) }
    }
}
