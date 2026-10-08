// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import UserNotifications
import WebKit

@MainActor
final class NotificationBridge: NSObject {
    static let shared = NotificationBridge()

    nonisolated static let handlerName = "linennotify"

    var tabResolver: ((WKWebView) -> BrowserTab?)?
    var linkOpener: ((URL, UUID?) -> Void)?
    var openWatchedPage: ((URL, UUID) -> Void)?

    private static let watchedURLKey = "linen.watch.url"
    private static let watchedProfileKey = "linen.watch.profile"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - The page's side

    nonisolated static let scriptSource = """
        (function () {
          if (!window.webkit || !window.webkit.messageHandlers
              || !window.webkit.messageHandlers.linennotify) { return; }
          var post = function (m) { window.webkit.messageHandlers.linennotify.postMessage(m); };
          var permission = 'default';
          var nextId = 1;
          var pending = {};
          function LinenNotification(title, options) {
            options = options || {};
            this.title = String(title);
            this.body = options.body ? String(options.body) : '';
            this.tag = options.tag ? String(options.tag) : '';
            this.onclick = null;
            this.onerror = null;
            post({ type: 'show', id: 0, title: this.title, body: this.body, tag: this.tag });
          }
          LinenNotification.prototype.close = function () {};
          Object.defineProperty(LinenNotification, 'permission', {
            get: function () { return permission; }
          });
          LinenNotification.requestPermission = function (callback) {
            var id = nextId++;
            return new Promise(function (resolve) {
              pending[id] = function (value) {
                if (callback) { try { callback(value); } catch (e) {} }
                resolve(value);
              };
              post({ type: 'request', id: id });
            });
          };
          LinenNotification.maxActions = 0;
          window.Notification = LinenNotification;
          window.__linenNotify = {
            setPermission: function (value) { permission = value; },
            resolve: function (id, value) {
              if (value === 'granted' || value === 'denied') { permission = value; }
              var f = pending[id];
              delete pending[id];
              if (f) { f(value); }
            }
          };
          post({ type: 'hello', id: 0 });
        })();
        """

    // MARK: - Requests

    private func handle(_ body: [String: Any], from webView: WKWebView) {
        guard let type = body["type"] as? String,
              let tab = tabResolver?(webView) else { return }
        switch type {
        case "hello":
            let state: String = if tab.permissions.isGranted(.notifications) {
                "granted"
            } else if tab.permissions.menuPolicy(for: .notifications) == .deny {
                "denied"
            } else {
                "default"
            }
            push(permission: state, to: webView)
        case "request":
            guard let jsID = body["id"] as? Int else { return }
            let origin = SitePermissions.origin(for: webView.url)
            Task { [weak self, weak webView, weak tab] in
                guard let tab else { return }
                let outcome = await tab.permissions.outcome(.notifications)
                var answer: String
                switch outcome {
                case .granted:
                    let allowed = (try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])) ?? false
                    answer = allowed ? "granted" : "denied"
                case .denied:
                    answer = "denied"
                case .undecided:
                    answer = "default"
                }
                guard let self, let webView,
                      SitePermissions.origin(for: webView.url) == origin else { return }
                resolve(jsID, with: answer, in: webView)
            }
        case "show":
            // Per spec the constructor fails silently without permission.
            guard tab.permissions.isGranted(.notifications) else { return }
            deliver(
                title: body["title"] as? String ?? "",
                text: body["body"] as? String ?? "",
                tag: body["tag"] as? String ?? "",
                from: tab
            )
        default:
            break
        }
    }

    private func resolve(_ jsID: Int, with answer: String, in webView: WKWebView) {
        webView.evaluateJavaScript(
            "window.__linenNotify && window.__linenNotify.resolve(\(jsID), '\(answer)')",
            completionHandler: nil
        )
    }

    private func push(permission: String, to webView: WKWebView) {
        webView.evaluateJavaScript(
            "window.__linenNotify && window.__linenNotify.setPermission('\(permission)')",
            completionHandler: nil
        )
    }

    // MARK: - Delivery

    private func deliver(title: String, text: String, tag: String, from tab: BrowserTab) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        content.subtitle = tab.permissions.displayHost
        let identifier = tag.isEmpty
            ? UUID().uuidString
            : "\(tab.permissions.displayHost)#\(tag)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func post(title: String, subtitle: String, body: String, identifier: String, link: URL, profileID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.userInfo = ["link": link.absoluteString, "profile": profileID.uuidString]
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            } else if settings.authorizationStatus == .denied {
                return
            }
            try? await center.add(request)
        }
    }

    // MARK: - Page watches

    func requestAlerts() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func announce(_ watch: PageWatch, _ notice: PageWatchCenter.Notice, profileID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = watch.title.isEmpty ? watch.place : watch.title
        content.subtitle = watch.place
        switch notice {
        case .met(let message):
            content.body = message
            content.sound = .default
        case .unreachable:
            content.body = String(localized: "Linen can’t read this page anymore, so it stopped watching it.")
        case .expired:
            content.body = String(localized: "Linen stopped watching this page after 30 days.")
        }
        content.userInfo = [
            Self.watchedURLKey: watch.url.absoluteString,
            Self.watchedProfileKey: profileID.uuidString,
        ]
        let request = UNNotificationRequest(identifier: watch.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - WKScriptMessageHandler

extension NotificationBridge: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame,
              let webView = message.webView,
              let body = message.body as? [String: Any] else { return }
        handle(body, from: webView)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationBridge: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NSApp.activate()
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let address = info[Self.watchedURLKey] as? String,
           let url = URL(string: address),
           let profileID = (info[Self.watchedProfileKey] as? String).flatMap(UUID.init(uuidString:)) {
            openWatchedPage?(url, profileID)
            return
        }
        if let link = (info["link"] as? String).flatMap(URL.init(string:)) {
            linkOpener?(link, (info["profile"] as? String).flatMap(UUID.init(uuidString:)))
        }
    }
}
