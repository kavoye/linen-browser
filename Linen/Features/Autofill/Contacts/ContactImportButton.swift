// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Contacts
import ContactsUI
import SwiftUI

struct ContactImportButton: NSViewRepresentable {
    let onSelect: (CNContact) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: String(localized: "Import from Contacts…"), target: context.coordinator, action: #selector(Coordinator.show(_:)))
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.onSelect = onSelect
    }

    static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) {
        coordinator.picker.close()
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var onSelect: (CNContact) -> Void
        let picker = CNContactPicker()

        init(onSelect: @escaping (CNContact) -> Void) {
            self.onSelect = onSelect
            super.init()
            picker.delegate = self
        }

        @objc func show(_ sender: NSButton) {
            picker.showRelative(to: sender.bounds, of: sender, preferredEdge: .maxY)
        }

        func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {
            onSelect(contact)
            picker.close()
        }
    }
}
