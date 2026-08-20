// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import WebKit

@MainActor
enum PagePrinting {
    static func begin(for webView: WKWebView, then finished: (() -> Void)? = nil) {
        let id = ObjectIdentifier(webView)
        guard let window = webView.window,
              !(webView.superview is WebViewParkingShelf),
              !printing.contains(id)
        else {
            finished?()
            return
        }

        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds

        printing.insert(id)
        let sheet = PrintSheetDelegate {
            printing.remove(id)
            finished?()
        }
        sheets.append(sheet)
        operation.runModal(
            for: window,
            delegate: sheet,
            didRun: #selector(PrintSheetDelegate.printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    private static var printing: Set<ObjectIdentifier> = []
    private static var sheets: [PrintSheetDelegate] = []

    fileprivate static func forget(_ sheet: PrintSheetDelegate) {
        sheets.removeAll { $0 === sheet }
    }
}

@MainActor
private final class PrintSheetDelegate: NSObject {
    private let finished: () -> Void

    init(finished: @escaping () -> Void) {
        self.finished = finished
        super.init()
    }

    @objc func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let finished = finished
        PagePrinting.forget(self)
        finished()
    }
}
