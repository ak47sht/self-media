import Foundation

/// 调试日志工具
/// 通过环境变量 MEDIALIB_DEBUG=1 启用日志输出
enum DebugLog {
    /// 是否启用调试日志（通过环境变量或编译标志控制）
    static var enabled: Bool {
        #if DEBUG
        // Debug 构建默认开启，可通过环境变量关闭
        return ProcessInfo.processInfo.environment["MEDIALIB_DEBUG"] != "0"
        #else
        // Release 构建默认关闭，可通过环境变量开启
        return ProcessInfo.processInfo.environment["MEDIALIB_DEBUG"] == "1"
        #endif
    }
    
    /// 打印日志（仅在启用时）
    static func log(_ items: Any..., separator: String = " ", file: String = #file, function: String = #function, line: Int = #line) {
        guard enabled else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let message = items.map { "\($0)" }.joined(separator: separator)
        print("🎬 [\(fileName):\(line)] \(message)")
    }
    
    /// 打印带标签的日志
    static func log(_ tag: String, _ items: Any..., separator: String = " ") {
        guard enabled else { return }
        let message = items.map { "\($0)" }.joined(separator: separator)
        print("🎬 [\(tag)] \(message)")
    }
}
