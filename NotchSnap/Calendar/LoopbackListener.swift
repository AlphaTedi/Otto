import Foundation
import Network

// MARK: - LoopbackListener — catches Google's OAuth redirect
//
// Google redirects the browser to http://127.0.0.1:<port>/?code=… after
// consent. Something has to be listening on that port for one request. This is
// that: a TCP listener bound to loopback on an ephemeral port, alive only for
// the duration of the sign-in.
//
// Deliberately minimal — it reads one request line, pulls the query out of it,
// answers with a short HTML page, and stops. It is not an HTTP server and must
// never grow into one; nothing outside this machine can reach it (loopback
// only) and it exists for a few seconds.

final class LoopbackListener: @unchecked Sendable {
    let port: UInt16

    private let listener: NWListener
    private let queue: DispatchQueue
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private let lock = NSLock()

    /// Async factory rather than a throwing `init` — the original blocked the
    /// CALLING thread on a `DispatchSemaphore` while waiting for the kernel to
    /// hand back a port, and `GoogleOAuth` (the only caller) is `@MainActor`,
    /// so that wait ran on the main actor: up to 5 seconds of a frozen app on
    /// every single sign-in attempt, worse on a fresh install where the
    /// network stack's first touch is slower to spin up. "Could not bind a
    /// loopback port" (Marcello, 2026-08-09) is that 5s timeout firing, not a
    /// real bind failure — `.any` already asks the kernel for a free port, so
    /// a genuine collision is close to impossible. `withCheckedThrowingContinuation`
    /// suspends the calling Task instead of blocking a thread, and the timeout
    /// is now generous enough to survive a cold start.
    static func create() async throws -> LoopbackListener {
        let parameters = NWParameters.tcp
        // Loopback only: never expose this to the network.
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            // Port 0 asks the kernel for a free one, so we never collide with
            // whatever else the user is running.
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw GoogleOAuth.AuthError.listenerFailed(error.localizedDescription)
        }

        let queue = DispatchQueue(label: "com.notchsnap.oauth.loopback")
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resume(.success(listener.port?.rawValue ?? 0))
                case .failed(let error):
                    box.resume(.failure(GoogleOAuth.AuthError.listenerFailed(error.localizedDescription)))
                case .cancelled:
                    box.resume(.failure(GoogleOAuth.AuthError.listenerFailed("listener was cancelled")))
                default:
                    break
                }
            }
            listener.start(queue: queue)
            // 10s, not 5: generous enough for a cold network stack on a
            // freshly launched, freshly notarized app to still succeed rather
            // than time out on what would otherwise be a working bind.
            queue.asyncAfter(deadline: .now() + 10) {
                // Tear down rather than leave a listener dangling if `.ready`
                // shows up just after this fires — harmless either way since
                // ContinuationBox only lets the first resume count, but a
                // menu-bar app that runs all day shouldn't leak a listener on
                // the rare slow-start case.
                listener.cancel()
                box.resume(.failure(GoogleOAuth.AuthError.listenerFailed(
                    "timed out waiting for the sign-in listener to start")))
            }
        }
        guard port != 0 else {
            listener.cancel()
            throw GoogleOAuth.AuthError.listenerFailed("could not bind a loopback port")
        }

        let result = LoopbackListener(listener: listener, queue: queue, port: port)
        listener.newConnectionHandler = { [weak result] connection in
            result?.handle(connection)
        }
        return result
    }

    private init(listener: NWListener, queue: DispatchQueue, port: UInt16) {
        self.listener = listener
        self.queue = queue
        self.port = port
    }

    /// Resolves with the authorization code, or throws if the user denied or
    /// closed the browser without finishing.
    func awaitCode() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if finished { lock.unlock(); return }
                self.continuation = continuation
                lock.unlock()
            }
        } onCancel: {
            self.finish(.failure(GoogleOAuth.AuthError.cancelled))
        }
    }

    func stop() {
        listener.cancel()
    }

    // MARK: Plumbing

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let result = Self.parse(requestLine: request)

            let body = Self.responsePage(success: {
                if case .success = result { return true } else { return false }
            }())
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            self.finish(result)
        }
    }

    /// Pulls `code` (or `error`) out of "GET /?code=… HTTP/1.1".
    private static func parse(requestLine request: String) -> Result<String, Error> {
        guard let line = request.split(separator: "\r\n").first ?? request.split(separator: "\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://127.0.0.1\(path)") else {
            return .failure(GoogleOAuth.AuthError.denied("malformed redirect"))
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            return .failure(GoogleOAuth.AuthError.denied(error))
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return .failure(GoogleOAuth.AuthError.denied("no authorization code in the redirect"))
        }
        return .success(code)
    }

    /// Resume exactly once — the browser may well hit the port more than once
    /// (favicon requests are the usual culprit).
    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success(let code): continuation?.resume(returning: code)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    private static func responsePage(success: Bool) -> String {
        let title = success ? "Otto is connected" : "Sign-in was not completed"
        let detail = success
            ? "You can close this tab and go back to Otto."
            : "Nothing was changed. Close this tab and try again from Otto."
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body style="font: 15px -apple-system, sans-serif; background:#111; color:#eee;
                     display:flex; align-items:center; justify-content:center; height:100vh; margin:0">
          <div style="text-align:center">
            <div style="font-size:19px; margin-bottom:8px">\(title)</div>
            <div style="color:#888">\(detail)</div>
          </div>
        </body></html>
        """
    }
}

/// Resumes a `CheckedContinuation` exactly once, whichever of two racing
/// closures gets there first. `create()` arms both the listener's own ready
/// handler and a timeout fallback on the same continuation — resuming twice
/// is a hard crash, so this is the difference between "first one wins" and
/// "first one wins, unless the second one lands mid-flight and takes the
/// whole app down with it."
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<UInt16, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        switch result {
        case .success(let value): cont?.resume(returning: value)
        case .failure(let error): cont?.resume(throwing: error)
        }
    }
}
