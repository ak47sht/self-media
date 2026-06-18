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

struct VODResolvedStream {
    let url: String
    let referer: String?
    let userAgent: String?
    let sourcePageURL: String?
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

        if isDirectStreamURL(url) {
            return VODURLClassification(
                type: .directStream,
                originalURL: url,
                note: "直连视频流"
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


    static func isDirectStreamURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = URLComponents(string: trimmed)?.path.lowercased() ?? trimmed.lowercased()
        return path.hasSuffix(".m3u8")
            || path.range(of: #"\.(mp4|webm|mov|flv)$"#, options: .regularExpression) != nil
    }

    static func normalizeResolvedURL(_ rawValue: String, baseURL: String? = nil) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
        if value.hasPrefix("//") {
            let scheme = URL(string: baseURL ?? "")?.scheme ?? "https"
            value = "\(scheme):\(value)"
        } else if value.hasPrefix("/"), let baseURL, let base = URL(string: baseURL) {
            value = URL(string: value, relativeTo: base)?.absoluteString ?? value
        }
        guard isHTTPURL(value) else { return nil }
        return value
    }

    private static func isHTTPURL(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// 解析出源特定的第三方播放器 URL
    private static func resolveParserURL(sourceName: String, url: String) -> String? {
        let src = sourceName

        if src.hasPrefix("极速资源") {
            return buildParserURL(base: "https://jsjiexi.com/play/", url: url)
        }
        if src.hasPrefix("光速资源") {
            return buildParserURL(base: "https://www.guangsujx.com/m3u8/", url: url)
        }
        if src.hasPrefix("淘片资源") {
            return buildParserURL(base: "https://taopianapi.com/cjapi/m3u8/", url: url)
        }
        if src.hasPrefix("豪华资源") {
            return buildParserURL(base: "https://hhzyjiexi.com/play/", url: url)
        }

        return nil
    }

    private static func buildParserURL(base: String, url: String) -> String? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "url", value: url)]
        return components?.url?.absoluteString
    }

    /// 用 WebView 从网页/分享页中提取真实的视频流 URL
    func extractResolvedStream(from webPageURL: String) async throws -> VODResolvedStream {
        let coordinator = await MainActor.run { () -> WebViewCoordinator in
            let webView = WKWebView()
            let coordinator = WebViewCoordinator(
                webView: webView,
                targetURL: webPageURL
            )
            webView.navigationDelegate = coordinator
            return coordinator
        }

        // 等待 coordinator 完成（它会在完成时 resume 这个 continuation）
        let url = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    coordinator.setContinuation(continuation)
                    coordinator.start()
                }
            }
        } onCancel: {
            Task { @MainActor in
                coordinator.cancel()
            }
        }
        return VODResolvedStream(
            url: url,
            referer: webPageURL,
            userAgent: WebViewCoordinator.defaultUserAgent,
            sourcePageURL: webPageURL
        )
    }

    /// 旧调用点兼容：只返回标准化后的 URL 字符串。
    func extractStreamURL(from webPageURL: String) async throws -> String {
        try await extractResolvedStream(from: webPageURL).url
    }

    // MARK: - 旧 API（保留兼容）

    @available(*, deprecated, message: "Use extractStreamURL(from:) instead")
    func extractStreamURL_old(from webPageURL: String) async throws -> String {
        return try await extractStreamURL(from: webPageURL)
    }
}

// MARK: - WebView 协调器

private class WebViewCoordinator: NSObject, WKNavigationDelegate {
    static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private var webView: WKWebView?
    let targetURL: String
    private var continuation: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>? = nil
    private var timeoutTask: Task<Void, Never>?
    private var didFinish = false
    private var extractionRetryCount = 0

    init(webView: WKWebView, targetURL: String) {
        self.webView = webView
        self.targetURL = targetURL
        super.init()
    }

    deinit {
        timeoutTask?.cancel()
        if !didFinish, let c = continuation {
            c.resume(throwing: NSError(domain: "VODURLResolver", code: -99, userInfo: [NSLocalizedDescriptionKey: "WebView 解析器已提前释放"]))
        }
    }

    // MARK: - Public API

    @MainActor
    func setContinuation(_ c: CheckedContinuation<String, Error>) {
        if let pending = pendingResult {
            pendingResult = nil
            timeoutTask?.cancel()
            switch pending {
            case .success(let url):
                c.resume(returning: url)
            case .failure(let error):
                c.resume(throwing: error)
            }
        } else {
            self.continuation = c
        }
    }

    @MainActor
    func cancel() {
        resumeWithError(NSError(domain: "VODURLResolver", code: -5, userInfo: [NSLocalizedDescriptionKey: "WebView 解析已取消"]))
    }

    @MainActor
    func start() {
        guard let webView = webView else {
            resumeWithError(NSError(domain: "VODURLResolver", code: -4, userInfo: [NSLocalizedDescriptionKey: "WebView 已释放"]))
            return
        }
        webView.navigationDelegate = self
        webView.customUserAgent = Self.defaultUserAgent

        // 30 秒超时
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self = self else { return }
            await self.handleTimeout()
        }

        guard let url = URL(string: targetURL) else {
            resumeWithError(NSError(domain: "VODURLResolver", code: -2, userInfo: [NSLocalizedDescriptionKey: "无效的 URL"]))
            return
        }

        webView.load(URLRequest(url: url))
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluateStreamExtraction(on: webView)
    }

    private func evaluateStreamExtraction(on webView: WKWebView) {
        let js = """
        (function() {
            function isPlayableUrl(value) {
                if (typeof value !== 'string' || value.length === 0) { return false; }
                if (value.indexOf('blob:') === 0) { return false; }
                return /\\.(m3u8|mp4|webm|mov|flv)(\\?|$)/i.test(value);
            }

            var videoEl = document.querySelector('video');
            if (videoEl && isPlayableUrl(videoEl.src)) {
                return videoEl.src;
            }

            var sourceEl = document.querySelector('video source');
            if (sourceEl && isPlayableUrl(sourceEl.src)) {
                return sourceEl.src;
            }

            var commonVars = ['video_url', 'videoUrl', 'playUrl', 'play_url', 'url', 'src', 'video'];
            for (var i = 0; i < commonVars.length; i++) {
                var val = window[commonVars[i]];
                if (isPlayableUrl(val)) {
                    return val;
                }
            }

            var scripts = document.getElementsByTagName('script');
            for (var i = 0; i < scripts.length; i++) {
                var content = scripts[i].textContent || scripts[i].innerText;
                var m3u8Match = content.match(/https?:\\/\\/[^\\s"'<>]+\\.m3u8[^\\s"'<>]*/);
                if (m3u8Match) {
                    return m3u8Match[0];
                }
                var mp4Match = content.match(/https?:\\/\\/[^\\s"'<>]+\\.mp4[^\\s"'<>]*/);
                if (mp4Match) {
                    return mp4Match[0];
                }
                var otherVideoMatch = content.match(/https?:\\/\\/[^\\s"'<>]+\\.(webm|mov|flv)[^\\s"'<>]*/);
                if (otherVideoMatch) {
                    return otherVideoMatch[0];
                }
            }

            if (window.performance && typeof window.performance.getEntriesByType === 'function') {
                var entries = window.performance.getEntriesByType('resource') || [];
                for (var j = entries.length - 1; j >= 0; j--) {
                    var resourceUrl = entries[j] && entries[j].name;
                    if (isPlayableUrl(resourceUrl)) {
                        return resourceUrl;
                    }
                }
            }

            return '';
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                self.resumeWithError(error)
                return
            }

            if let urlString = result as? String,
               let normalizedURL = VODURLResolver.normalizeResolvedURL(urlString, baseURL: self.targetURL) {
                self.resumeWithSuccess(normalizedURL)
            } else {
                self.scheduleExtractionRetry(on: webView)
            }
        }
    }

    private func scheduleExtractionRetry(on webView: WKWebView) {
        guard !didFinish else { return }
        guard extractionRetryCount < 10 else {
            resumeWithError(NSError(domain: "VODURLResolver", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法从网页中提取视频流 URL"]))
            return
        }
        extractionRetryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak webView] in
            guard let self = self, let webView = webView, !self.didFinish else { return }
            self.evaluateStreamExtraction(on: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resumeWithError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resumeWithError(error)
    }

    // MARK: - Result Handling (all called on main thread by WKWebView)

    /// WKNavigationDelegate 回调保证在主线程，所以这里去掉 @MainActor 用 assumeIsolated
    private func handleTimeout() {
        MainActor.assumeIsolated {
            resumeWithError(NSError(domain: "VODURLResolver", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebView 解析超时"]))
        }
    }

    private func resumeWithSuccess(_ urlString: String) {
        guard !didFinish else { return }
        didFinish = true
        timeoutTask?.cancel()
        if let c = continuation {
            continuation = nil
            releaseHeldWebView()
            c.resume(returning: urlString)
        } else {
            pendingResult = .success(urlString)
            releaseHeldWebView()
        }
    }

    private func resumeWithError(_ error: Error) {
        guard !didFinish else { return }
        didFinish = true
        timeoutTask?.cancel()
        if let c = continuation {
            continuation = nil
            releaseHeldWebView()
            c.resume(throwing: error)
        } else {
            pendingResult = .failure(error)
            releaseHeldWebView()
        }
    }

    /// 断开 webView 的 navigationDelegate 并释放解析期间的强引用。
    private func releaseHeldWebView() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
    }
}
