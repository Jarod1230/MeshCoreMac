// MeshCoreMac/ViewModels/DiagnosticsViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsViewModel {

    enum CLIError: Error, LocalizedError {
        case invalidHex(String)
        var errorDescription: String? {
            switch self {
            case .invalidHex(let s): return "Ungültige Hex-Eingabe: '\(s)'"
            }
        }
    }

    private(set) var logEntries: [RxLogEntry] = []
    private(set) var batteryPercent: Int? = nil
    private(set) var storageUsed: Int? = nil
    private(set) var storageFree: Int? = nil
    private(set) var rssi: Int? = nil
    private(set) var noiseFloor: Int? = nil

    var cliInput: String = ""
    private(set) var cliHistory: [String] = []

    private let bluetoothService: any BluetoothServiceProtocol
    nonisolated(unsafe) private var listenerTask: Task<Void, Never>?
    private var started = false

    static let maxEntries = 200

    init(bluetoothService: any BluetoothServiceProtocol) {
        self.bluetoothService = bluetoothService
    }

    func start() async {
        guard !started else { return }
        started = true
        startListening()
    }

    func sendCLICommand() async throws {
        let trimmed = cliInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tokens = trimmed.split(separator: " ").map(String.init)
        var bytes: [UInt8] = []
        for token in tokens {
            guard let byte = UInt8(token, radix: 16) else {
                throw CLIError.invalidHex(token)
            }
            bytes.append(byte)
        }
        try bluetoothService.send(Data(bytes))
        cliHistory.insert(trimmed, at: 0)
        if cliHistory.count > 50 { cliHistory.removeLast() }
        cliInput = ""
    }

    func requestNodeStatus() async throws {
        try bluetoothService.send(MeshCoreProtocolService.encodeBattAndStorage())
    }

    func clearLog() {
        logEntries = []
    }

    private func startListening() {
        listenerTask?.cancel()
        listenerTask = Task {
            for await entry in self.bluetoothService.rxLogStream {
                guard !Task.isCancelled else { break }
                self.handleEntry(entry)
            }
        }
    }

    private func handleEntry(_ entry: RxLogEntry) {
        if logEntries.count >= Self.maxEntries {
            logEntries.removeFirst()
        }
        logEntries.append(entry)

        guard entry.direction == .incoming,
              let decoded = try? MeshCoreProtocolService.decodeFrame(entry.rawBytes) else { return }
        switch decoded {
        case .battAndStorage(let batt, let used, let free):
            batteryPercent = batt
            storageUsed = used
            storageFree = free
        case .noiseFloor(let r, let n):
            rssi = r
            noiseFloor = n
        default:
            break
        }
    }

    deinit {
        listenerTask?.cancel()
    }
}
