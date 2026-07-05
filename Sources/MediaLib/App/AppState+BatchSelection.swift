import Foundation
import MediaLibCore

extension AppState {
    func toggleSelectionMode() { selection.toggleMode() }

    func exitSelectionMode() { selection.exit() }

    func toggleItemSelection(_ id: String) { selection.toggleItem(id) }

    /// 在当前可见集合范围内全选 / 取消全选。
    func setSelection(_ ids: [String], selected: Bool) { selection.setSelection(ids, selected: selected) }

    /// 由 ID 集合还原为有序条目（按传入顺序），仅取库内存在的条目。
    func resolveSelectedItems(orderedBy ordered: [MediaItem]) -> [MediaItem] {
        selection.resolveSelected(orderedBy: ordered)
    }

    private var currentSelectionItems: [MediaItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    func batchMarkWatched(watched: Bool) {
        let targets = currentSelectionItems.filter { $0.type != .music }
        guard !targets.isEmpty else { return }
        markAllWatched(targets, watched: watched)
    }

    func batchSetWatchlist(_ watchlist: Bool) {
        let targets = currentSelectionItems.filter { $0.type != .music }
        guard !targets.isEmpty else { return }
        guard let mediaRepository else { return }
        var hadError = false
        for item in targets {
            updateWatchlistInMemory(id: item.id, watchlist: watchlist)
            do {
                try mediaRepository.setWatchlist(id: item.id, watchlist: watchlist)
            } catch {
                hadError = true
                logger?.log("批量更新想看状态失败：\(error.localizedDescription)", level: .warning)
            }
            syncTraktWatchlist(item, add: watchlist)
        }
        if hadError {
            alert = AppAlert(title: "部分更新失败", message: "有条目的想看状态未能更新。")
        } else {
            showFloatingNotice(
                title: watchlist ? "已加入想看" : "已从想看移除",
                message: "\(targets.count) 个内容",
                kind: watchlist ? .success : .info,
                duration: 3.2
            )
        }
    }

    func batchUpdateRating(_ rating: Double?) {
        let targets = currentSelectionItems
        guard !targets.isEmpty else { return }
        guard let mediaRepository else { return }
        var hadError = false
        for item in targets {
            updateRatingInMemory(id: item.id, rating: rating)
            do {
                try mediaRepository.updateRating(id: item.id, rating: rating)
            } catch {
                hadError = true
                logger?.log("批量更新评级失败：\(error.localizedDescription)", level: .warning)
            }
        }
        if hadError {
            alert = AppAlert(title: "部分更新失败", message: "有条目的评级未能更新。")
        } else {
            showFloatingNotice(
                title: rating == nil ? "已清除评级" : "评级已更新",
                message: "\(targets.count) 个内容 · \(userRatingNoticeSuffix(rating))",
                kind: .success,
                duration: 3.2
            )
        }
    }

    func batchClearPlaybackHistory() {
        let targets = currentSelectionItems.filter { $0.hasPlaybackTrace }
        guard !targets.isEmpty else { return }
        clearPlaybackHistory(targets)
    }

    /// 将已选条目从内部索引移除（不删除磁盘文件）。本地来源在下次扫描时可能重新入库。
    func batchRemoveFromLibrary() {
        let ids = Array(selectedItemIDs)
        guard !ids.isEmpty, let mediaRepository else { return }
        do {
            try mediaRepository.deleteItems(ids: ids)
            reload()
            exitSelectionMode()
        } catch {
            showError("批量移除失败", error)
        }
    }
}
