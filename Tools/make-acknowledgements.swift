#!/usr/bin/env swift

// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

//
// Writes Linen/Support/Acknowledgements.json from the resolved packages and
// from the vendored code in Tools/vendored.
//
//     swift Tools/make-acknowledgements.swift [checkouts-directory]
//
// Run the command from the repository root. If you give no directory, the
// script looks in build/DD/SourcePackages/checkouts, then in the DerivedData
// folder of Xcode. Resolve the packages one time before you run the script.
//
// Vendored code is code that is copied into the app instead of linked as a
// package. To add an entry: put its LICENSE in Tools/vendored/<name>/, then
// add the name, version and URL to `vendored` below.
//
// The output file is committed. The app reads it at runtime, and CI runs this
// script again and fails if the result is different. Thus the license text
// that the app shows always agrees with what the app links.

import Foundation

// MARK: - Input

struct Resolved: Decodable {
    struct Pin: Decodable {
        struct State: Decodable {
            let version: String?
            let revision: String
        }

        let identity: String
        let location: String
        let state: State
    }

    let pins: [Pin]
}

struct Package: Encodable {
    let name: String
    let version: String
    let url: String
    let license: String
    let text: String
}

struct Payload: Encodable {
    let packages: [Package]
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resolvedPath = root
    .appending(path: "Linen.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
let output = root.appending(path: "Linen/Support/Acknowledgements.json")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-acknowledgements: \(message)\n".utf8))
    exit(1)
}

guard let resolvedData = try? Data(contentsOf: resolvedPath),
      let resolved = try? JSONDecoder().decode(Resolved.self, from: resolvedData)
else {
    fail("cannot read \(resolvedPath.path). Run this from the repository root.")
}

// MARK: - Where the sources are

func candidateCheckouts() -> [URL] {
    if CommandLine.arguments.count > 1 {
        return [URL(fileURLWithPath: CommandLine.arguments[1])]
    }

    var candidates = [root.appending(path: "build/DD/SourcePackages/checkouts")]

    let derived = URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: "Library/Developer/Xcode/DerivedData")
    let builds = (try? fileManager.contentsOfDirectory(at: derived, includingPropertiesForKeys: nil)) ?? []
    candidates += builds
        .filter { $0.lastPathComponent.hasPrefix("Linen-") }
        .map { $0.appending(path: "SourcePackages/checkouts") }

    return candidates
}

func directories(in url: URL) -> [String] {
    ((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? [])
        .filter { name in
            var isDirectory: ObjCBool = false
            let path = url.appending(path: name).path
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
}

/// A checkouts folder that holds every pin. A folder from an older resolve
/// would silently ship a license for a package that is no longer linked.
func locateCheckouts() -> URL {
    let wanted = Set(resolved.pins.map(\.identity))

    for candidate in candidateCheckouts() {
        let found = Set(directories(in: candidate).map { $0.lowercased() })
        if wanted.isSubset(of: found) {
            return candidate
        }
    }

    fail("""
        no checkouts folder holds all \(wanted.count) resolved packages. \
        Run `xcodebuild -resolvePackageDependencies -project Linen.xcodeproj \
        -scheme Linen`, then run this script again.
        """)
}

let checkouts = locateCheckouts()

// MARK: - Reading a license

let licenseNames = ["license", "licence", "copying"]
let noticeNames = ["notice"]

func file(in directory: URL, named names: [String]) -> URL? {
    let entries = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    let match = entries.first { entry in
        let stem = (entry as NSString).deletingPathExtension.lowercased()
        return names.contains(stem)
    }
    return match.map { directory.appending(path: $0) }
}

func text(of url: URL) -> String {
    guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
}

func licenseName(of text: String) -> String {
    if text.contains("Apache License") && text.contains("Version 2.0") {
        return "Apache License 2.0"
    }
    if text.contains("Permission is hereby granted, free of charge") {
        return "MIT License"
    }
    if text.contains("Redistribution and use in source and binary forms") {
        return "BSD License"
    }
    if text.contains("GNU GENERAL PUBLIC LICENSE") {
        return "GNU General Public License"
    }
    if text.contains("Mozilla Public License") {
        return "Mozilla Public License 2.0"
    }
    return "See the license text"
}

// MARK: - Vendored code

struct Vendor {
    let name: String
    let version: String
    let url: String
}

let vendored = [
    Vendor(name: "thinking-orbs", version: "0.3.1", url: "https://github.com/Jakubantalik/thinking-orbs")
]

let vendoredPackages: [Package] = vendored.map { vendor in
    let directory = root.appending(path: "Tools/vendored/\(vendor.name)")
    guard let licenseFile = file(in: directory, named: licenseNames) else {
        fail("Tools/vendored/\(vendor.name) ships no license file.")
    }

    let body = text(of: licenseFile)
    return Package(
        name: vendor.name,
        version: vendor.version,
        url: vendor.url,
        license: licenseName(of: body),
        text: body
    )
}

// MARK: - Output

let byIdentity = Dictionary(
    uniqueKeysWithValues: directories(in: checkouts).map { ($0.lowercased(), $0) }
)

let packages: [Package] = resolved.pins.compactMap { pin in
    guard let folder = byIdentity[pin.identity] else {
        fail("no checkout for \(pin.identity) in \(checkouts.path)")
    }

    let directory = checkouts.appending(path: folder)
    guard let licenseFile = file(in: directory, named: licenseNames) else {
        fail("\(folder) ships no license file. Add its terms by hand before you release.")
    }

    var body = text(of: licenseFile)
    if let notice = file(in: directory, named: noticeNames) {
        body += "\n\n" + text(of: notice)
    }

    return Package(
        name: folder,
        version: pin.state.version ?? String(pin.state.revision.prefix(7)),
        url: pin.location.replacingOccurrences(of: ".git", with: ""),
        license: licenseName(of: body),
        text: body
    )
}

let allPackages = (packages + vendoredPackages)
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

guard let encoded = try? encoder.encode(Payload(packages: allPackages)) else {
    fail("cannot encode the result")
}

try? fileManager.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

do {
    try (String(decoding: encoded, as: UTF8.self) + "\n").write(to: output, atomically: true, encoding: .utf8)
} catch {
    fail("cannot write \(output.path): \(error.localizedDescription)")
}

print("make-acknowledgements: \(allPackages.count) packages → \(output.path)")
