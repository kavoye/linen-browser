// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Observation
import WebKit

@Observable
final class PasswordAutofill: NSObject, WKScriptMessageHandler {
    static let shared = PasswordAutofill()
    static let world = AutofillPage.world
    private static let handlerName = "linenPasswords"

    private(set) var profileID = Profile.originalID
    var isPrivate: Bool {
        profileID == Profile.privateID
    }

    @ObservationIgnored var extensions: () -> [InstalledExtension] = { [] }
    var isEnabled: Bool {
        !isPrivate && BrowserSettings.shared.fillsPasswords
            && PasswordExtensionPolicy.provider(in: extensions(), selectedID: BrowserSettings.shared.passwordExtensionID) == nil
    }
    @ObservationIgnored private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    @ObservationIgnored private let owners = NSMapTable<WKWebView, NSUUID>.weakToStrongObjects()
    @ObservationIgnored private let frames = NSMapTable<WKWebView, FrameList>.weakToStrongObjects()

    private final class FrameList: NSObject {
        var values: [String: WKFrameInfo] = [:]
        var mainDocumentID: String?
    }

    func refreshPolicy() {
        AutofillSaveCoordinator.shared.refreshPolicy()
        for view in frames.keyEnumerator().allObjects.compactMap({ $0 as? WKWebView }) {
            for frame in frames.object(forKey: view)?.values.values.map({ $0 }) ?? [] {
                applyPolicy(in: view, frame: frame)
            }
        }
    }

    private func applyPolicy(in view: WKWebView, frame: WKFrameInfo) {
        let enabled = isEnabled && owners.object(forKey: view) as UUID? == profileID
        Task {
            _ = try? await view.callAsyncJavaScript(
                "globalThis.__linenPasswords?.setEnabled(enabled);", arguments: ["enabled": enabled],
                in: frame, contentWorld: Self.world
            )
        }
    }

    func use(profileID: UUID) {
        self.profileID = profileID
        refreshPolicy()
    }

    func install(in webView: WKWebView) {
        owners.setObject(profileID as NSUUID, forKey: webView)
        let controller = webView.configuration.userContentController
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        AutofillPage.install(in: controller)
        controller.addUserScript(WKUserScript(
            source: PasswordAutofillScript.clientSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: Self.world
        ))
        controller.add(self, contentWorld: Self.world, name: Self.handlerName)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, owners.object(forKey: webView) as UUID? == profileID else { return }
        if let body = message.body as? [String: Any], body["action"] as? String == "ready" {
            AutofillDiagnostics.note(.scriptReady, kind: .password)
            guard let documentID = body["documentID"] as? String, UUID(uuidString: documentID) != nil else { return }
            let list = frames.object(forKey: webView) ?? FrameList()
            if message.frameInfo.isMainFrame, list.mainDocumentID != documentID {
                list.values = [:]
                list.mainDocumentID = documentID
            }
            if list.values[documentID] == nil, list.values.count >= 100,
               let oldest = list.values.keys.first(where: { $0 != list.mainDocumentID }) {
                list.values[oldest] = nil
            }
            list.values[documentID] = message.frameInfo
            frames.setObject(list, forKey: webView)
            applyPolicy(in: webView, frame: message.frameInfo)
            return
        }
        AutofillSuggestions.shared.receive(message, kind: .password, profileID: profileID,
                                            world: Self.world, bridge: "__linenPasswords")
    }

    static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil
    }

}
