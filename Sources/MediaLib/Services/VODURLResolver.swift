import Foundation
import WebKit

enum VODURLType {
    case directStream       // 可直接播放 (.m3u8, .mp4, .webm, .mov)
    case needsParser(String) // 需要第三方解析器
    case webPage            // 网页/分享页，需要用 WebView 解析
    case unsupported        // 不支持的 URL
}

struct VODURLClassification {
    let type: VODURLType
    let originalURL: String
    let note: String
}

actor VODURLResolver {
    
    /// 分类 VOD URL
    static func classify(_ urlString: String, sourceName: String = "") -> VODURLClassification {
        let url = urlString.trimmingCharacters(in: .whitespaces)
        
        guard !url.isEmpty else {
            return VODURLClassification(
                type: .unsupported,
                originalURL: url,
                note: "URL 为空"
            )
        }
        
        // 检查是否需要源特定的解析器
        if let parserURL = resolveParserURL(sourceName: sourceName, url: url) {
            return VODURLClassification(
                type: .needsParser(parserURL),
                originalURL: url,
                note: "需要第三方解析器：\(sourceName)"
            )
        }
        
        // 检查是否是直连流
        let lowercased = url.lowercased()
        
        if lowercased.contains(".m3u8") {
            return VODURLClassification(
                type: .directStream,
                originalURL: url,
                note: "直连 m3u8 流"
            )
        }
        
        if lowercased.range(of: #"\.(mp4|webm|mov)(\?|$)"#, options: .regularExpression) != nil {
            return VODURLClassification(
                type: .directStream,
                originalURL: url,
                note: "直连 MP4/WebM/MOV 视频"
            )
        }
        
        // 其他 HTTP(S) URL：可能是网页播放器或分享页
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return VODURLClassification(
                type: .webPage,
                originalURL: url,
                note: "网页/分享页，需要解析真实流地址"
            )
        }
        
        return VODURLClassification(
            type: .unsupported,
            originalURL: url,
            note: "不支持的 URL 格式"
        )
    }
    
    /// 解析出源特定的第三方播放器 URL
    private static func resolveParserURL(sourceName: String, url: String) -> String? {
        let src = sourceName
        
        if src.hasPrefix("极速资源") {
            return "https://jsjiexi.com/play/?url=" + url
        }
        if src.hasPrefix("光速资源") {
            return "https://www.guangsujx.com/m3u8/?url=" + url
        }
        if src.hasPrefix("淘片资源") {
            return "https://taopianapi.com/cjapi/m3u8/?url=" + url
        }
        if src.hasPrefix("豪华资源") {
            return "https://hhzyjiexi.com/play/?url=" + url
        }
        
        return nil
    }
    
    /// 用 WebView 从网页/分享页中提取真实的视频流 URL
    func extractStreamURL(from webPageURL: String) async throws -> String {
        let coordinator = await MainActor.run { () -> WebViewCoordinator in
            let webView = WKWebView()
            let coordinator = WebViewCoordinator(
                webView: webView,
                targetURL: webPageURL
            )
            // navigationDelegate 强引用 coordinator\n            webView.navigationDelegate = coordinator\n            coordinator.start()\n            return coordinator\n        }

        // 等待 coordinator 完成（它会在完成时 resume 这个 continuation）
        return try await withCheckedThrowingContinuation { continuation in
            coordinator.continuation = continuation
            // 如果 coordinator 已经完成（race condition），continuation 需要立即被 resume
            coordinator.flushPendingResult()
        }
    }
    
    // MARK: - 旧 API（保留兼容）
    
    @available(*, deprecated, message: "Use extractStreamURL(from:) instead")
    func extractStreamURL_old(from webPageURL: String) async throws -> String {
        return try await extractStreamURL(from: webPageURL)
    }
}

// MARK: - WebView 协调器

private class WebViewCoordinator: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let targetURL: String
    var continuation: CheckedContinuation<String, Error>?
    var pendingResult: Result<String, Error>? = nil
    var timeoutTask: Task<Void, Never>?
    
    init(webView: WKWebView, targetURL: String) {
        self.webView = webView
        self.targetURL = targetURL
        super.init()
    }
    
    func start() {
        webView.navigationDelegate = self
        
        // 30 秒超时
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await self?.resumeWithError(NSError(domain: "VODURLResolver", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebView 解析超时"]))
        }
        
        guard let url = URL(string: targetURL) else {
            resumeWithError(NSError(domain: "VODURLResolver", code: -2, userInfo: [NSLocalizedDescriptionKey: "无效的 URL"]))
            return
        }
        
        webView.load(URLRequest(url: url))
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 页面加载完成，执行 JavaScript 提取视频 URL
        let js = """
        (function() {
            // 尝试多种方式提取视频 URL
            
            // 1. 查找 video 标签的 src
            var videoEl = document.querySelector('video');
            if (videoEl && videoEl.src) {
                return videoEl.src;
            }
            
            // 2. 查找 video source 标签
            var sourceEl = document.querySelector('video source');
            if (sourceEl && sourceEl.src) {
                return sourceEl.src;
            }
            
            // 3. 从全局变量中提取（常见的播放器变量名）
            var commonVars = ['video_url', 'videoUrl', 'playUrl', 'play_url', 'url', 'src', 'video'];
            for (var i = 0; i < commonVars.length; i++) {
                var val = window[commonVars[i]];
                if (typeof val === 'string' && (val.indexOf('.m3u8') !== -1 || val.indexOf('.mp4') !== -1)) {
                    return val;
                }
            }
            
            // 4. 从脚本内容中提取 URL（正则匹配）
            var scripts = document.getElementsByTagName('script');
            for (var i = 0; i < scripts.length; i++) {
                var content = scripts[i].textContent || scripts[i].innerText;
                // 匹配 m3u8 URL
                var m3u8Match = content.match(/https?:\\/\\/[^\\s"'<>]+\\.m3u8[^\\s"'<>]*/);
                if (m3u8Match) {
                    return m3u8Match[0];
                }
                // 匹配 mp4 URL
                var mp4Match = content.match(/https?:\\/\\/[^\\s"'<>]+\\.mp4[^\\s"'<>]*/);
                if (mp4Match) {
                    return mp4Match[0];
                }
            }
            
            return null;
        })();
        """
        
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                self.resumeWithError(error)
                return
            }
            
            if let urlString = result as? String, !urlString.isEmpty {
                self.resumeWithSuccess(urlString)
            } else {
                self.resumeWithError(NSError(domain: "VODURLResolver", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法从网页中提取视频流 URL"]))
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resumeWithError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resumeWithError(error)
    }
    
    private func resumeWithSuccess(_ urlString: String) {
        timeoutTask?.cancel()
        if let c = continuation {
            continuation = nil
            c.resume(returning: urlString)
        } else {
            pendingResult = .success(urlString)
        }
    }
    
    private func resumeWithError(_ error: Error) {
        timeoutTask?.cancel()
        if let c = continuation {
            continuation = nil
            c.resume(throwing: error)
        } else {
            pendingResult = .failure(error)
        }
    }
    
    func flushPendingResult() {
        if let result = pendingResult {
            pendingResult = nil
            switch result {
            case .success(let url): resumeWithSuccess(url)
            case .failure(let error): resumeWithError(error)
            }
        }
    }
}
