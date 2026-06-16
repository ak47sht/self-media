import Foundation
import os

/// 调试日志工具
/// 通过环境变量 MEDIALIB_DEBUG=1 启用日志输出
/// 日志输出到系统日志（Console.app 可查看）
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
    
    // 使用 os.Logger 以便在 Console.app 中可见
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.local.MediaLib", category: "DebugLog")
    
    /// 打印日志（仅在启用时）
    static func log(_ items: Any..., separator: String = " ", file: String = #file, function: String = #function, line: Int = #line) {
        guard enabled else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let message = items.map { "\($0)" }.joined(separator: separator)
        let logMessage = "🎬 [\(fileName):\(line)] \(message)"
        
        // 输出到系统日志（Console.app 可查看）
        logger.debug("\(logMessage, privacy: .public)")
        
        // 同时输出到标准输出（Xcode 控制台）
        print(logMessage)
    }
    
    /// 打印带标签的日志
    static func log(_ tag: String, _ items: Any..., separator: String = " ") {
        guard enabled else { return }
        let message = items.map { "\($0)" }.joined(separator: separator)
        let logMessage = "🎬 [\(tag)] \(message)"
        
        // 输出到系统日志
        logger.debug("\(logMessage, privacy: .public)")
        
        // 输出到标准输出
        print(logMessage)
    }
}
