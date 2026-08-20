// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Security

nonisolated enum CRXVerifier {
    enum VerificationError: LocalizedError {
        case notACRX
        case unsupportedVersion(Int)
        case malformedHeader
        case noMatchingProof
        case signatureInvalid

        var errorDescription: String? {
            switch self {
            case .notACRX:
                String(localized: "The downloaded file is not a supported extension package")
            case .unsupportedVersion(let version):
                String(localized: "Unsupported CRX container version \(version)")
            case .malformedHeader:
                String(localized: "The extension package header is malformed")
            case .noMatchingProof:
                String(localized: "The package isn’t signed by this extension’s own key")
            case .signatureInvalid:
                String(localized: "The extension package failed signature verification")
            }
        }
    }

    static func verifiedZip(from data: Data, expectedID: String) throws -> Data {
        let (header, zip) = try split(data)
        let (proofs, signedHeaderData) = try parseHeader(header)

        for proof in proofs where derivedID(fromPublicKey: proof.publicKey) == expectedID {
            if verify(
                signature: proof.signature,
                publicKeySPKI: proof.publicKey,
                signedHeaderData: signedHeaderData,
                zip: zip
            ) {
                return zip
            }
            throw VerificationError.signatureInvalid
        }
        throw VerificationError.noMatchingProof
    }

    // MARK: - Container

    static func split(_ data: Data) throws -> (header: Data, zip: Data) {
        let bytes = [UInt8](data)
        guard bytes.count > 16, bytes.prefix(4).elementsEqual("Cr24".utf8) else {
            throw VerificationError.notACRX
        }
        let version = le32(bytes, at: 4)
        guard version == 3 else { throw VerificationError.unsupportedVersion(Int(version)) }
        let headerLength = Int(le32(bytes, at: 8))
        let headerStart = 12
        let zipStart = headerStart + headerLength
        guard headerLength > 0, bytes.count > zipStart else { throw VerificationError.notACRX }
        return (
            header: Data(bytes[headerStart..<zipStart]),
            zip: Data(bytes[zipStart..<bytes.count])
        )
    }

    // MARK: - Header (only the fields verification needs)

    struct Proof {
        let publicKey: Data
        let signature: Data
    }

    static func parseHeader(_ header: Data) throws -> (proofs: [Proof], signedHeaderData: Data) {
        var proofs: [Proof] = []
        var signedHeaderData: Data?
        var reader = ProtobufReader(header)
        while let field = reader.next() {
            switch field.number {
            case 2:
                if let proof = parseProof(field.bytes) {
                    proofs.append(proof)
                }
            case 10000:
                signedHeaderData = field.bytes
            default:
                continue
            }
        }
        guard let signedHeaderData else { throw VerificationError.malformedHeader }
        guard !proofs.isEmpty else { throw VerificationError.noMatchingProof }
        return (proofs, signedHeaderData)
    }

    private static func parseProof(_ bytes: Data) -> Proof? {
        var publicKey: Data?
        var signature: Data?
        var reader = ProtobufReader(bytes)
        while let field = reader.next() {
            switch field.number {
            case 1:
                publicKey = field.bytes
            case 2:
                signature = field.bytes
            default:
                continue
            }
        }
        guard let publicKey, let signature else { return nil }
        return Proof(publicKey: publicKey, signature: signature)
    }

    // MARK: - Identity

    static func derivedID(fromPublicKey spki: Data) -> String {
        var id = ""
        id.reserveCapacity(32)
        for byte in SHA256.hash(data: spki).prefix(16) {
            id.unicodeScalars.append(UnicodeScalar(UInt8(97) + (byte >> 4)))
            id.unicodeScalars.append(UnicodeScalar(UInt8(97) + (byte & 0x0F)))
        }
        return id
    }

    // MARK: - Signature

    static func verify(signature: Data, publicKeySPKI: Data, signedHeaderData: Data, zip: Data) -> Bool {
        guard let key = rsaKey(fromSPKI: publicKeySPKI) else { return false }

        var message = Data("CRX3 SignedData\u{00}".utf8)
        var length = UInt32(signedHeaderData.count).littleEndian
        withUnsafeBytes(of: &length) { message.append(contentsOf: $0) }
        message.append(signedHeaderData)
        message.append(zip)

        return SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            signature as CFData,
            nil
        )
    }

    static func rsaKey(fromSPKI spki: Data) -> SecKey? {
        guard let pkcs1 = pkcs1PublicKey(fromSPKI: spki) else { return nil }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        return SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil)
    }

    static func pkcs1PublicKey(fromSPKI spki: Data) -> Data? {
        var outer = DERReader([UInt8](spki))
        guard let sequence = outer.read(), sequence.tag == 0x30 else { return nil }
        var inner = DERReader(sequence.value)
        guard let algorithm = inner.read(), algorithm.tag == 0x30 else { return nil }
        _ = algorithm
        guard let bitString = inner.read(), bitString.tag == 0x03,
              bitString.value.first == 0x00 else { return nil }
        return Data(bitString.value.dropFirst())
    }

    // MARK: - Byte helpers

    private static func le32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    struct ProtobufReader {
        private let bytes: [UInt8]
        private var index = 0

        init(_ data: Data) {
            bytes = [UInt8](data)
        }

        struct Field {
            let number: Int
            let bytes: Data
        }

        mutating func next() -> Field? {
            while index < bytes.count {
                guard let tag = varint() else { return nil }
                let number = Int(tag >> 3)
                let wireType = Int(tag & 0x07)
                switch wireType {
                case 0:
                    guard varint() != nil else { return nil }
                case 1:
                    guard advance(8) else { return nil }
                case 5:
                    guard advance(4) else { return nil }
                case 2:
                    guard let length = varint(), advance(Int(length)) else { return nil }
                    let end = index
                    return Field(number: number, bytes: Data(bytes[(end - Int(length))..<end]))
                default:
                    return nil
                }
            }
            return nil
        }

        private mutating func advance(_ count: Int) -> Bool {
            guard count >= 0, index + count <= bytes.count else { return false }
            index += count
            return true
        }

        private mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 {
                    return result
                }
                shift += 7
                if shift >= 64 {
                    return nil
                }
            }
            return nil
        }
    }

    struct DERReader {
        private let bytes: [UInt8]
        private var index = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        struct TLV {
            let tag: UInt8
            let value: [UInt8]
        }

        mutating func read() -> TLV? {
            guard index + 1 < bytes.count else { return nil }
            let tag = bytes[index]
            index += 1
            var length = Int(bytes[index])
            index += 1
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count > 0, count <= 4, index + count <= bytes.count else { return nil }
                length = 0
                for _ in 0..<count {
                    length = (length << 8) | Int(bytes[index])
                    index += 1
                }
            }
            guard length >= 0, index + length <= bytes.count else { return nil }
            let value = Array(bytes[index..<index + length])
            index += length
            return TLV(tag: tag, value: value)
        }
    }
}
