// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

struct OpenAIMCPSettingsView: View {
    let providerID: String
    @Binding var servers: [OpenAIMCPServer]
    var oauthSetup = OpenAIMCPOAuthSetup()
    @State private var showsEditor = false
    @State private var label = ""
    @State private var destination = ""
    @State private var allowedTools = ""
    @State private var token = ""
    @State private var error: String?
    @State private var editingID: UUID?
    @State private var useOAuth = false
    @State private var issuer = ""
    @State private var clientID = ""
    @State private var scope = ""
    @State private var resource = ""
    @State private var operationTask: Task<Void, Never>?
    @State private var operationID: UUID?
    @State private var operationMessage = String(localized: "Waiting for sign-in…")
    @State private var discoveredIssuers: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The assistant can use tools from connected MCP services. Linen asks you to approve each tool call.")
                .font(.callout).foregroundStyle(.secondary)
            SettingsCard {
                if servers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "link").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("No connected services").font(.headline)
                        Text("Add a service using the connection details it provides.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 28)
                }
                ForEach(servers) { server in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: server.label).font(.callout.weight(.medium))
                            Text(verbatim: server.destination).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if server.oauth != nil {
                            Button(server.authorizationRevision == nil ? "Sign in" : "Sign in again") { signIn(server) }
                        }
                        Menu {
                            Button("Edit connection…") { edit(server); showsEditor = true }
                            if server.oauth != nil && server.authorizationRevision != nil {
                                Button("Sign out") { signOut(server) }
                            }
                            Button("Remove connection", role: .destructive) { remove(server) }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Connection actions")
                    }.padding(.vertical, 14)
                    if server.id != servers.last?.id {
                        RowSeparator()
                    }
                }
            }.disabled(operationTask != nil)
            SettingsButton(title: "Add connection…", isProminent: true, symbol: "plus") { clear(); showsEditor = true }
                .disabled(operationTask != nil)
            if let error, !showsEditor {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            if operationTask != nil && !showsEditor {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(operationMessage).font(.callout)
                    Button("Cancel", action: cancelOperation)
                }
            }
        }
        .sheet(isPresented: $showsEditor, onDismiss: cancelOperation) {
            OpenAISettingsSheet(title: editingID == nil ? "Add connection" : "Edit connection") {
                VStack(alignment: .leading, spacing: 14) {
                    OpenAIConnectionField(title: "Name", placeholder: "Name of the service", text: $label)
                    OpenAIConnectionField(title: "Server address", placeholder: "HTTPS MCP URL or connector ID", text: $destination)
                    DisclosureGroup("Limit available tools") {
                        OpenAIConnectionField(title: "Allowed tools", placeholder: "Tool names, separated by commas", text: $allowedTools)
                    }
                    Picker("Sign-in method", selection: $useOAuth) {
                        Text("Access token or no sign-in").tag(false)
                        Text("Sign in with the service").tag(true)
                    }
                    if useOAuth {
                        Button("Find sign-in settings", action: discoverOAuth)
                            .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if discoveredIssuers.count > 1 {
                            Picker("Authorization server", selection: $issuer) {
                                ForEach(discoveredIssuers, id: \.self) { Text(verbatim: $0).tag($0) }
                            }
                            .onChange(of: issuer) { clientID = "" }
                        }
                        OpenAIConnectionField(title: "Authorization server", placeholder: "HTTPS OAuth issuer", text: $issuer)
                        OpenAIConnectionField(title: "Client ID", placeholder: "Registered public client ID", text: $clientID)
                        Button("Register public client", action: registerClient)
                            .disabled(issuer.isEmpty || !clientID.isEmpty)
                        OpenAIConnectionField(title: "Requested access", placeholder: "Scopes, separated by spaces", text: $scope)
                        OpenAIConnectionField(title: "Resource URL", placeholder: "Only if the service requires it", text: $resource)
                        Text("Register this redirect URI with your authorization server:")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: OpenAIMCPOAuthConfiguration.redirect).font(.caption).textSelection(.enabled)
                        Text("Enter a registered public client ID, or register one if the service allows it. Save the connection, then select Sign in.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Access token").font(.callout.weight(.medium))
                            SecureField(editingID == nil ? "Optional" : "Leave blank to keep the saved token", text: $token)
                                .accessibilityLabel("Access token")
                        }
                    }
                    if useOAuth {
                        Text("Access tokens are sent to your configured OpenAI provider. Refresh tokens stay in Keychain and are sent only to the authorization server.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Authorization tokens are stored in Keychain and sent to your configured OpenAI provider for the MCP connection.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                    HStack {
                        Button(editingID == nil ? "Add connection" : "Save connection", action: save)
                        Button("Cancel") { clear(); showsEditor = false }
                    }

                }.textFieldStyle(.roundedBorder).disabled(operationTask != nil)
                if operationTask != nil {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(operationMessage).font(.callout)
                        Button("Cancel", action: cancelOperation)
                    }
                }
            }
        }
        .onDisappear(perform: cancelOperation)
    }

    private func edit(_ server: OpenAIMCPServer) {
        editingID = server.id
        label = server.label
        destination = server.destination
        allowedTools = server.allowedTools.joined(separator: ", ")
        token = ""
        useOAuth = server.oauth != nil
        issuer = server.oauth?.issuer ?? ""
        clientID = server.oauth?.clientID ?? ""
        scope = server.oauth?.scope ?? ""
        resource = server.oauth?.resource ?? ""
        error = nil
        discoveredIssuers = []
    }

    private func save() {
        let authorization = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = servers.first { $0.id == editingID }
        var candidate = OpenAIMCPServer(
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedTools: allowedTools.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            requiresAuthorization: useOAuth || !authorization.isEmpty || old?.requiresAuthorization == true,
            oauth: useOAuth ? .init(issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines),
                                   clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                                   scope: scope.trimmingCharacters(in: .whitespacesAndNewlines),
                                   resource: resource.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        )
        if let old {
            candidate.id = old.id
            candidate.authorizationRevision = old.authorizationRevision
        }
        do {
            _ = try candidate.definition(authorization: candidate.requiresAuthorization ? "validation-only" : nil)
            guard servers.count < 20 || old != nil,
                  !servers.contains(where: { $0.id != candidate.id && $0.label == candidate.label }) else { throw OpenAIMCPFailure.configuration }
            guard candidate.oauth != nil || old == nil || (old?.destination == candidate.destination && old?.oauth == nil)
                    || !candidate.requiresAuthorization || !authorization.isEmpty else {
                error = String(localized: "Enter a new authorization token when changing this connection's destination.")
                return
            }
            if old?.oauth != candidate.oauth || old?.destination != candidate.destination {
                try OpenAIMCPOAuthManager.shared.disconnect(serverID: candidate.id, providerID: providerID)
                candidate.authorizationRevision = nil
            }
            let manual = useOAuth ? "" : authorization
            if useOAuth || !manual.isEmpty, let message = CredentialStore.saveMCPAuthorization(manual, providerID: providerID, serverID: candidate.id) {
                error = message
                return
            }
            if !useOAuth, !authorization.isEmpty {
                candidate.authorizationRevision = UUID()
            }
            var updated = servers.filter { $0.id != candidate.id }
            updated.append(candidate)
            servers = updated
            clear()
            showsEditor = false
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ server: OpenAIMCPServer) {
        do { try OpenAIMCPOAuthManager.shared.disconnect(serverID: server.id, providerID: providerID) } catch {
            self.error = error.localizedDescription
            return
        }
        if let message = CredentialStore.saveMCPAuthorization("", providerID: providerID, serverID: server.id) {
            error = message
            return
        }
        servers.removeAll { $0.id == server.id }
        if editingID == server.id {
            clear()
        }
    }

    private func clear() {
        editingID = nil
        label = ""
        destination = ""
        allowedTools = ""
        token = ""
        useOAuth = false
        issuer = ""
        clientID = ""
        scope = ""
        resource = ""
        error = nil
        discoveredIssuers = []
    }

    private func signIn(_ server: OpenAIMCPServer) {
        guard let window = NSApp.keyWindow else { error = OpenAIMCPOAuthFailure.unavailable.localizedDescription; return }
        let identity = UUID()
        operationID = identity
        operationMessage = String(localized: "Waiting for sign-in…")
        error = nil
        let session = OpenAIMCPOAuthSession(window: window)
        operationTask = Task { @MainActor in
            defer {
                if operationID == identity {
                    operationTask = nil; operationID = nil
                }
            }
            do {
                let credential = try await OpenAIMCPOAuthManager.shared.authorize(server: server, authenticate: session.authenticate)
                try Task.checkCancellation()
                guard operationID == identity, servers.first(where: { $0.id == server.id }) == server else { return }
                try OpenAIMCPOAuthManager.shared.commit(credential, server: server, providerID: providerID)
                var updated = server
                updated.authorizationRevision = credential.sessionID
                servers = servers.map { $0.id == server.id ? updated : $0 }
            } catch {
                if operationID == identity, !Task.isCancelled {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func signOut(_ server: OpenAIMCPServer) {
        do {
            try OpenAIMCPOAuthManager.shared.disconnect(serverID: server.id, providerID: providerID)
            var updated = server
            updated.authorizationRevision = nil
            servers = servers.map { $0.id == server.id ? updated : $0 }
        } catch { self.error = error.localizedDescription }
    }

    private func cancelOperation() {
        operationID = nil
        operationTask?.cancel()
        operationTask = nil
    }

    private func discoverOAuth() {
        let target = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        startSetup(message: String(localized: "Discovering OAuth settings…")) {
            let result = try await oauthSetup.discover(destination: target)
            return .discovered(result)
        }
    }

    private func registerClient() {
        let configuration = OpenAIMCPOAuthConfiguration(issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines), clientID: "", scope: scope, resource: resource)
        startSetup(message: String(localized: "Registering public client…")) {
            let client = try await oauthSetup.register(issuer: configuration.issuer, scope: configuration.scope, resource: configuration.resource)
            return .registered(client)
        }
    }

    private enum SetupResult {
        case discovered(OpenAIMCPOAuthDiscovery)
        case registered(String)
    }

    private func startSetup(message: String, perform: @escaping @MainActor () async throws -> SetupResult) {
        let identity = UUID()
        operationID = identity
        operationMessage = message
        error = nil
        operationTask = Task { @MainActor in
            defer {
                if operationID == identity {
                    operationTask = nil; operationID = nil
                }
            }
            do {
                let result = try await perform()
                try Task.checkCancellation()
                guard operationID == identity else { return }
                switch result {
                case .discovered(let result):
                    discoveredIssuers = result.issuers
                    let selected = result.issuers.contains(issuer) ? issuer : result.issuers[0]
                    if selected != issuer { clientID = "" }
                    issuer = selected
                    scope = result.scope
                    resource = result.resource
                case .registered(let client):
                    clientID = client
                }
            } catch {
                if operationID == identity, !Task.isCancelled {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

private struct OpenAIConnectionField: View {
    let title: LocalizedStringResource
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium))
            TextField(placeholder, text: $text).accessibilityLabel(Text(title))
        }
    }
}
