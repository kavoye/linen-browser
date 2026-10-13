// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import Linen

@Suite(.timeLimit(.minutes(1)))
struct MCPStdioTransportTests {
    @Test func pipeDeliversPartialAndCoalescedFramesAndFinishesAtEOF() async throws {
        let input = Pipe()
        let output = Pipe()
        let transport = MCPStdioTransport(
            input: input.fileHandleForReading.fileDescriptor,
            output: output.fileHandleForWriting.fileDescriptor
        )
        try await transport.connect()
        var messages = await transport.receive().makeAsyncIterator()
        try input.fileHandleForWriting.write(contentsOf: Data("{\"id\":".utf8))
        try input.fileHandleForWriting.write(contentsOf: Data("1}\n\n{\"id\":2}\n".utf8))
        #expect(try await messages.next() == Data("{\"id\":1}".utf8))
        #expect(try await messages.next() == Data("{\"id\":2}".utf8))
        try input.fileHandleForWriting.close()
        #expect(try await messages.next() == nil)
        await transport.disconnect()
    }

    @Test func outputIsNewlineDelimitedAndDisconnectFinishesIdleInput() async throws {
        let input = Pipe()
        let output = Pipe()
        let transport = MCPStdioTransport(
            input: input.fileHandleForReading.fileDescriptor,
            output: output.fileHandleForWriting.fileDescriptor
        )
        try await transport.connect()
        try await transport.send(Data("{\"id\":3}".utf8))
        #expect(output.fileHandleForReading.availableData == Data("{\"id\":3}\n".utf8))
        var messages = await transport.receive().makeAsyncIterator()
        await transport.disconnect()
        #expect(try await messages.next() == nil)
        await #expect(throws: (any Error).self) {
            try await transport.send(Data())
        }
    }

    @Test func oversizedInputFailsWithoutWaitingForANewline() async throws {
        let input = Pipe()
        let output = Pipe()
        let transport = MCPStdioTransport(
            input: input.fileHandleForReading.fileDescriptor,
            output: output.fileHandleForWriting.fileDescriptor
        )
        try await transport.connect()
        let writer = Task.detached {
            try input.fileHandleForWriting.write(contentsOf: Data(repeating: 65, count: MCPMessageFramer.maximumBytes + 1))
        }
        await #expect(throws: (any Error).self) {
            for try await _ in await transport.receive() {}
        }
        try await writer.value
        await transport.disconnect()
    }

    @Test(arguments: [false, true])
    func releasingTransportWhileInputStaysOpen(_ disconnectFirst: Bool) async throws {
        let input = Pipe()
        let output = Pipe()
        weak var released: MCPStdioTransport?
        do {
            let transport = MCPStdioTransport(
                input: input.fileHandleForReading.fileDescriptor,
                output: output.fileHandleForWriting.fileDescriptor
            )
            released = transport
            try await transport.connect()
            if disconnectFirst {
                await transport.disconnect()
            }
        }
        #expect(await waitUntil { released == nil })
    }
}
