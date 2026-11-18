import Foundation

/// One event from the Mattermost WebSocket (`posted`, `post_edited`, `channel_viewed`, `typing`, ...).
public struct WebSocketEvent: Decodable, Sendable {
    public let event: String
    public let data: JSONValue?
    public let broadcast: JSONValue?
    public let seq: Int?
}

/// Connection state, so the UI can show "Connecting…" and the store knows when to catch up.
public enum WebSocketState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
}

/// Mattermost WebSocket with automatic reconnect and exponential backoff.
///
/// Usage: `for await event in client.events { ... }` after `connect()`.
/// After every reconnect, consumers should refetch anything changed since the last
/// event they processed (see `lastEventAt`), because events are not replayed.
public actor WebSocketClient {
    public nonisolated let events: AsyncStream<WebSocketEvent>
    public nonisolated let states: AsyncStream<WebSocketState>
    private let eventContinuation: AsyncStream<WebSocketEvent>.Continuation
    private let stateContinuation: AsyncStream<WebSocketState>.Continuation

    private let token: String
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var seq = 1
    private var attempt = 0
    private var shouldRun = false
    public private(set) var lastEventAt: Date?

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
        (events, eventContinuation) = AsyncStream.makeStream(of: WebSocketEvent.self)
        (states, stateContinuation) = AsyncStream.makeStream(of: WebSocketState.self)
    }

    public func connect() {
        shouldRun = true
        open()
    }

    /// Sends a client action (e.g. `user_typing`). Dropped silently when not connected.
    public func sendAction(_ action: String, data: [String: String]) async {
        guard let task else { return }
        let payload: [String: Any] = ["seq": nextSeq(), "action": action, "data": data]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else { return }
        try? await task.send(.string(text))
    }

    public func disconnect() {
        shouldRun = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        stateContinuation.yield(.disconnected)
    }

    private func open() {
        guard shouldRun else { return }
        stateContinuation.yield(.connecting)

        var request = URLRequest(url: ServerConfig.webSocketURL)
        request.setValue(ServerConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        Task { await self.authenticate(task) }
        Task { await self.receiveLoop(task) }
    }

    private func authenticate(_ task: URLSessionWebSocketTask) async {
        let challenge: [String: Any] = [
            "seq": nextSeq(),
            "action": "authentication_challenge",
            "data": ["token": token],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: challenge),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await task.send(.string(text))
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        let decoder = JSONDecoder()
        while true {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: continue
                }
                // Replies to our own actions carry `status`/`seq_reply` and no `event`; skip them.
                guard let event = try? decoder.decode(WebSocketEvent.self, from: data) else { continue }
                if event.event == "hello" {
                    attempt = 0
                    stateContinuation.yield(.connected)
                }
                lastEventAt = Date()
                eventContinuation.yield(event)
            } catch {
                await scheduleReconnect(after: task)
                return
            }
        }
    }

    private func scheduleReconnect(after failed: URLSessionWebSocketTask) async {
        guard shouldRun, failed === task else { return }
        stateContinuation.yield(.disconnected)
        attempt += 1
        let delay = min(30.0, pow(2.0, Double(attempt - 1))) // 1, 2, 4 … 30s
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        open()
    }

    private func nextSeq() -> Int {
        defer { seq += 1 }
        return seq
    }
}
