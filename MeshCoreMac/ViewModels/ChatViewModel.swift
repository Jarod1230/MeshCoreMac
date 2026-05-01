// MeshCoreMac/ViewModels/ChatViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private let bluetoothService: any BluetoothServiceProtocol
    private let messageStore: MessageStore

    let conversation: MeshMessage.Kind
    private(set) var messages: [MeshMessage] = []
    var errorMessage: String? = nil
    var inputText: String = ""

    nonisolated(unsafe) private var listenerTask: Task<Void, Never>?

    init(
        bluetoothService: any BluetoothServiceProtocol,
        messageStore: MessageStore,
        conversation: MeshMessage.Kind
    ) {
        self.bluetoothService = bluetoothService
        self.messageStore = messageStore
        self.conversation = conversation
    }

    func loadMessages() async {
        do {
            messages = try await messageStore.fetchMessages(for: conversation)
        } catch {
            errorMessage = "Nachrichten konnten nicht geladen werden: \(error.localizedDescription)"
        }
        startListening()
    }

    func send(text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let channelIndex: UInt8
        let contactId: String?
        switch conversation {
        case .channel(let idx): channelIndex = UInt8(idx); contactId = nil
        case .direct(let cid):  channelIndex = 0;           contactId = cid
        }

        let frame = try MeshCoreProtocolService.encodeSendTextMessage(
            text: text, channelIndex: channelIndex, recipientId: contactId
        )
        try bluetoothService.send(frame)

        let msg = MeshMessage(
            id: UUID(),
            kind: conversation,
            senderName: "Ich",
            text: text,
            timestamp: Date(),
            routing: nil,
            deliveryStatus: .sending,
            isIncoming: false
        )
        messages.append(msg)
        try await messageStore.save(msg)
        inputText = ""
    }

    // MARK: - Incoming Frame Listener

    private func startListening() {
        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            guard let self else { return }
            for await frameData in bluetoothService.incomingFrames {
                guard !Task.isCancelled else { break }
                await self.handleFrame(frameData)
            }
        }
    }

    private func handleFrame(_ data: Data) async {
        do {
            let decoded = try MeshCoreProtocolService.decodeFrame(data)
            switch decoded {
            case .newChannelMessage(let msg):
                guard case .channel(let idx) = msg.kind,
                      case .channel(let ours) = conversation,
                      idx == ours else { return }
                messages.append(msg)
                try await messageStore.save(msg)

            case .newDirectMessage(let msg):
                guard case .direct(let cid) = msg.kind,
                      case .direct(let ours) = conversation,
                      cid == ours else { return }
                messages.append(msg)
                try await messageStore.save(msg)

            case .messageAck(let msgId):
                if let idx = messages.firstIndex(where: { $0.id.uuidString == msgId }) {
                    messages[idx].deliveryStatus = .delivered
                    try await messageStore.updateDeliveryStatus(
                        messageId: messages[idx].id, status: .delivered
                    )
                }

            case .deviceInfo:
                break

            case .nodeStatus:
                break
            }
        } catch {
            // Protokoll-Fehler gehen in den Diagnose-Log (Task 12)
        }
    }

    deinit {
        listenerTask?.cancel()
    }
}
