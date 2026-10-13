// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CoreLocation
import Foundation
import WebKit

@MainActor
final class GeolocationBridge: NSObject {
    static let shared = GeolocationBridge()

    nonisolated static let handlerName = "linengeo"

    var tabResolver: ((WKWebView) -> BrowserTab?)?

    private let manager = CLLocationManager()

    private struct Request {
        weak var webView: WKWebView?
        let jsID: Int
        let isWatch: Bool
        let origin: String
    }

    private func isCurrent(_ request: Request) -> Bool {
        guard let webView = request.webView else { return false }
        return SitePermissions.origin(for: webView.url) == request.origin
    }

    private var oneShots: [Request] = []
    private var watches: [Request] = []
    private var awaitingAuthorization: [() -> Void] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - The page's side

    nonisolated static let scriptSource = """
        (function () {
          if (!window.webkit || !window.webkit.messageHandlers
              || !window.webkit.messageHandlers.linengeo) { return; }
          var post = function (m) { window.webkit.messageHandlers.linengeo.postMessage(m); };
          var nextId = 1;
          var pending = {};
          var geo = {
            getCurrentPosition: function (success, error, options) {
              var id = nextId++;
              pending[id] = { success: success, error: error };
              post({ type: 'get', id: id });
            },
            watchPosition: function (success, error, options) {
              var id = nextId++;
              pending[id] = { success: success, error: error, watch: true };
              post({ type: 'watch', id: id });
              return id;
            },
            clearWatch: function (id) {
              delete pending[id];
              post({ type: 'clear', id: id });
            }
          };
          Object.defineProperty(navigator, 'geolocation', { value: geo, configurable: true });
          window.__linenGeo = {
            position: function (id, coords, timestamp) {
              var p = pending[id];
              if (!p) { return; }
              if (!p.watch) { delete pending[id]; }
              try { p.success({ coords: coords, timestamp: timestamp }); } catch (e) {}
            },
            failure: function (id, code, message) {
              var p = pending[id];
              if (!p) { return; }
              if (!p.watch) { delete pending[id]; }
              if (p.error) {
                try {
                  p.error({ code: code, message: message,
                            PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 });
                } catch (e) {}
              }
            }
          };
        })();
        """

    // MARK: - Requests

    nonisolated static func parse(_ body: Any) -> (type: String, jsID: Int)? {
        guard let body = body as? [String: Any],
              let type = body["type"] as? String,
              let jsID = body["id"] as? Int
        else { return nil }
        return (type, jsID)
    }

    private func handle(type: String, jsID: Int, from webView: WKWebView) {
        switch type {
        case "get", "watch":
            let isWatch = type == "watch"
            guard let tab = tabResolver?(webView) else {
                fail(jsID, in: webView, code: 2, message: "Unavailable")
                return
            }
            let origin = SitePermissions.origin(for: webView.url)
            Task { [weak self, weak webView, weak tab] in
                let answer = await tab?.permissions.decide(.location) ?? false
                guard let self, let tab, let webView,
                      SitePermissions.origin(for: webView.url) == origin else { return }
                guard answer else {
                    fail(jsID, in: webView, code: 1, message: "Permission denied")
                    return
                }
                begin(
                    Request(webView: webView, jsID: jsID, isWatch: isWatch, origin: origin),
                    for: tab
                )
            }
        case "clear":
            watches.removeAll { $0.webView === webView && $0.jsID == jsID }
            refreshLiveAndPower()
        default:
            break
        }
    }

    private func begin(_ request: Request, for tab: BrowserTab) {
        switch manager.authorizationStatus {
        case .notDetermined:
            awaitingAuthorization.append { [weak self] in
                guard let self, isCurrent(request), let webView = request.webView,
                      let tab = tabResolver?(webView) else { return }
                begin(request, for: tab)
            }
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            if let webView = request.webView {
                fail(request.jsID, in: webView, code: 2, message: "Location is unavailable")
            }
            return
        default:
            break
        }

        if request.isWatch {
            watches.append(request)
            tab.onLocationRevoked = { [weak self, weak webView = request.webView] in
                guard let webView else { return }
                self?.stopWatches(for: webView)
            }
        } else {
            oneShots.append(request)
        }
        refreshLiveAndPower()
        if request.isWatch, let last = manager.location {
            deliver(last, to: [request])
        }
        if watches.isEmpty {
            manager.requestLocation()
        }
    }

    func stopWatches(for webView: WKWebView) {
        watches.removeAll { $0.webView === webView || $0.webView == nil }
        refreshLiveAndPower()
    }

    private func refreshLiveAndPower() {
        watches.removeAll { !isCurrent($0) }
        if watches.isEmpty {
            manager.stopUpdatingLocation()
        } else {
            manager.startUpdatingLocation()
        }
        var liveViews = Set<ObjectIdentifier>()
        for watch in watches {
            guard let view = watch.webView else { continue }
            liveViews.insert(ObjectIdentifier(view))
            tabResolver?(view)?.permissions.setLive(.location, true)
        }
        for request in oneShots {
            guard let view = request.webView,
                  !liveViews.contains(ObjectIdentifier(view)) else { continue }
            tabResolver?(view)?.permissions.setLive(.location, false)
        }
    }

    // MARK: - Answers

    private func deliver(_ location: CLLocation, to requests: [Request]) {
        for request in requests {
            guard isCurrent(request), let webView = request.webView else { continue }
            let coordinate = location.coordinate
            let coords: [String: Any] = [
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "altitude": location.altitude,
                "altitudeAccuracy": location.verticalAccuracy,
                "heading": location.course >= 0 ? location.course : NSNull(),
                "speed": location.speed >= 0 ? location.speed : NSNull(),
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: coords),
                  let json = String(data: data, encoding: .utf8) else { continue }
            let timestamp = Int(location.timestamp.timeIntervalSince1970 * 1000)
            webView.evaluateJavaScript(
                "window.__linenGeo && window.__linenGeo.position(\(request.jsID), \(json), \(timestamp))",
                completionHandler: nil
            )
        }
    }

    private func fail(_ jsID: Int, in webView: WKWebView, code: Int, message: String) {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript(
            "window.__linenGeo && window.__linenGeo.failure(\(jsID), \(code), \"\(escaped)\")",
            completionHandler: nil
        )
    }
}

// MARK: - WKScriptMessageHandler

extension GeolocationBridge: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.frameInfo.isMainFrame,
              let webView = message.webView,
              let parsed = Self.parse(message.body)
        else { return }
        handle(type: parsed.type, jsID: parsed.jsID, from: webView)
    }
}

// MARK: - CLLocationManagerDelegate

extension GeolocationBridge: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let parked = awaitingAuthorization
        awaitingAuthorization = []
        for resume in parked {
            resume()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let waiting = oneShots
        oneShots = []
        deliver(latest, to: waiting)
        deliver(latest, to: watches)
        refreshLiveAndPower()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        let waiting = oneShots
        oneShots = []
        for request in waiting {
            guard isCurrent(request), let webView = request.webView else { continue }
            fail(
                request.jsID,
                in: webView,
                code: denied ? 1 : 2,
                message: denied ? "Permission denied" : "Position unavailable"
            )
        }
    }
}
