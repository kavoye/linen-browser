// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Observation
import WebKit

@Observable
final class ContactAutofill: NSObject, WKScriptMessageHandler {
    static let shared = ContactAutofill()
    static let world = AutofillPage.world
    private static let handlerName = "linenContactAutofill"

    private(set) var profileID = Profile.originalID
    var isPrivate: Bool {
        profileID == Profile.privateID
    }
    @ObservationIgnored private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    @ObservationIgnored private let owners = NSMapTable<WKWebView, NSUUID>.weakToStrongObjects()

    func use(profile: Profile) {
        self.profileID = profile.id
        AutofillSuggestions.shared.reset()
    }

    func install(in webView: WKWebView) {
        owners.setObject(profileID as NSUUID, forKey: webView)
        let controller = webView.configuration.userContentController
        guard !controllers.contains(controller) else { return }
        controllers.add(controller)
        AutofillPage.install(in: controller)
        controller.addUserScript(WKUserScript(
            source: ContactAutofillScript.clientSource, injectionTime: .atDocumentStart,
            forMainFrameOnly: false, in: Self.world
        ))
        controller.add(self, contentWorld: Self.world, name: Self.handlerName)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView, owners.object(forKey: webView) as UUID? == profileID else { return }
        AutofillSuggestions.shared.receive(message, kind: .contact, profileID: profileID,
                                            world: Self.world, bridge: "__linenContactAutofill")
    }

    static func isSecure(_ url: URL) -> Bool {
        SavedPassword.origin(for: url) != nil
    }
}
