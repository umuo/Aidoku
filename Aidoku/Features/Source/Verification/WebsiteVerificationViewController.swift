import UIKit
import WebKit

/// 手动与自动流程共用验证页；原生 API 检查通过才恢复请求。
@MainActor
final class WebsiteVerificationViewController: UIViewController, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    private let policy: WebsiteVerificationPolicy
    private let sourceKey: String
    private let preferredUserAgent: String?
    private let entryURL: URL
    private var completion: (@MainActor (Result<Void, Error>) -> Void)?
    private let webView: WKWebView
    private let statusLabel = UILabel()
    private var operation: Task<Void, Never>?
    private var lifetime: Task<Void, Never>?
    private var checking = false
    private var finished = false
    private var ready = false

    private lazy var doneButton = UIBarButtonItem(
        title: NSLocalizedString("WEBSITE_VERIFICATION_RETRY"), style: .done, target: self, action: #selector(checkAccess)
    )
    private lazy var reloadButton = UIBarButtonItem(
        barButtonSystemItem: .refresh, target: self, action: #selector(reloadPage)
    )

    init(
        policy: WebsiteVerificationPolicy, sourceKey: String, userAgent: String?, entryURL: URL? = nil,
        completion: (@MainActor (Result<Void, Error>) -> Void)? = nil
    ) {
        self.policy = policy
        self.sourceKey = sourceKey
        preferredUserAgent = userAgent
        self.entryURL = entryURL.flatMap { policy.allowsNavigation(to: $0) ? $0 : nil } ?? policy.baseURL
        self.completion = completion
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("WEBSITE_VERIFICATION")
        navigationItem.prompt = policy.baseURL.host
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItems = [doneButton, reloadButton]
        doneButton.isEnabled = false
        reloadButton.isEnabled = false
        webView.navigationDelegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.text = policy.baseURL.host
        statusLabel.accessibilityTraits = .updatesFrequently
        let stack = UIStackView(arrangedSubviews: [statusLabel, webView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        operation = Task { [weak self] in
            guard let self else {
                return
            }
            let userAgent: String?
            if let preferredUserAgent {
                userAgent = preferredUserAgent
            } else {
                userAgent = await UserAgentProvider.shared.getUserAgent()
            }
            guard !Task.isCancelled else {
                return
            }
            guard let userAgent, !userAgent.isEmpty else {
                statusLabel.text = NSLocalizedString("WEBSITE_VERIFICATION_NETWORK_ERROR")
                return
            }
            webView.customUserAgent = userAgent
            await VerificationCookieBridge.importCookies(for: policy.baseURL, into: webView.configuration.websiteDataStore.httpCookieStore)
            guard !Task.isCancelled else {
                return
            }
            ready = true
            doneButton.isEnabled = true
            reloadButton.isEnabled = true
            reloadPage()
        }
        lifetime = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000_000)
            } catch {
                return
            }
            guard let self, !finished else {
                return
            }
            finishVerification(.failure(WebsiteVerificationError.timedOut))
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.presentationController?.delegate = self
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        stopOperations()
        notifyCompletion(.failure(WebsiteVerificationError.canceled))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            stopOperations()
            notifyCompletion(.failure(WebsiteVerificationError.canceled))
        }
    }

    private func stopOperations() {
        finished = true
        operation?.cancel()
        operation = nil
        lifetime?.cancel()
        lifetime = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func notifyCompletion(_ result: Result<Void, Error>) {
        let callback = completion
        completion = nil
        callback?(result)
    }

    private func finishVerification(_ result: Result<Void, Error>, refresh: Bool = false) {
        guard !finished else {
            return
        }
        stopOperations()
        // 先关闭窗口再释放等待者，防止下一验证窗口叠在关闭动画上。
        let callback = completion
        completion = nil
        let key = sourceKey
        if case .failure = result {
            // 进入后台或取消时，不依赖关闭动画结束才释放网络等待。
            callback?(result)
            dismiss(animated: true)
            return
        }
        dismiss(animated: true) {
            callback?(result)
            if refresh {
                NotificationCenter.default.post(name: .init("refresh-content"), object: key)
            }
        }
    }

    func cancelVerification() {
        finishVerification(.failure(WebsiteVerificationError.canceled))
    }

    @objc private func close() {
        cancelVerification()
    }

    @objc private func enteredBackground() {
        if completion != nil {
            finishVerification(.failure(WebsiteVerificationError.unavailable))
        }
    }

    @objc private func reloadPage() {
        guard ready, !checking, !finished else {
            return
        }
        statusLabel.text = NSLocalizedString("WEBSITE_VERIFICATION_INSTRUCTIONS")
        let request = URLRequest(url: entryURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        webView.load(request)
    }

    @objc private func checkAccess() {
        guard ready, !checking, !finished else {
            return
        }
        checking = true
        isModalInPresentation = true
        navigationController?.isModalInPresentation = true
        doneButton.isEnabled = false
        reloadButton.isEnabled = false
        statusLabel.text = NSLocalizedString("WEBSITE_VERIFICATION_CHECKING")
        operation = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                checking = false
                isModalInPresentation = false
                navigationController?.isModalInPresentation = false
                doneButton.isEnabled = true
                reloadButton.isEnabled = true
            }
            await VerificationCookieBridge.exportCookies(for: policy.baseURL, from: webView.configuration.websiteDataStore.httpCookieStore)
            guard !Task.isCancelled, !finished else {
                return
            }
            var request = policy.probeRequest
            request.setValue(webView.customUserAgent, forHTTPHeaderField: "User-Agent")
            request = VerificationCookieHeader.applying(to: request)
            do {
                // 不调用源 actor 或验证处理器，避免与等待中的旧 WASM 网络桥互锁。
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, !finished else {
                    return
                }
                if policy.isSuccessfulProbe(response: response, data: data) {
                    VerificationEligibility.record(
                        sourceKey: sourceKey, host: policy.baseURL.host!, userAgent: webView.customUserAgent!
                    )
                    finishVerification(.success(()), refresh: completion == nil)
                } else {
                    statusLabel.text = NSLocalizedString("WEBSITE_VERIFICATION_STILL_BLOCKED")
                }
            } catch {
                if !Task.isCancelled, !finished {
                    statusLabel.text = NSLocalizedString("WEBSITE_VERIFICATION_NETWORK_ERROR")
                }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, policy.allowsNavigation(to: url) else {
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        statusLabel.text = NSLocalizedString("WEBSITE_VERIFICATION_NETWORK_ERROR")
    }

    private func showNavigationError(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled, !checking, !finished {
            statusLabel.text = NSLocalizedString("WEBSITE_VERIFICATION_NETWORK_ERROR")
        }
    }
}
