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
    private let queue = DispatchQueue(label: "com.notchsnap.oauth.loopback")
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private let lock = NSLock()

    init() throws {
        let parameters = NWParameters.tcp
        // Loopback only: never expose this to the network.
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        do {
            // Port 0 asks the kernel for a free one, so we never collide with
            // whatever else the user is running.
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw GoogleOAuth.AuthError.listenerFailed(error.localizedDescription)
        }

        // Wait for the kernel to hand us a port. `listener` is a local `let`
        // here (the stored property isn't initialised until `port` is), so the
        // closure captures the value, not self — and the port is published
        // through a lock rather than a captured var so strict concurrency is
        // satisfied.
        let ready = DispatchSemaphore(value: 0)
        let boundPort = PortBox()
        let handle = listener
        handle.stateUpdateHandler = { state in
            switch state {
            case .ready:
                boundPort.value = handle.port?.rawValue ?? 0
                ready.signal()
            case .failed, .cancelled:
                ready.signal()
            default:
                break
            }
        }
        handle.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        guard boundPort.value != 0 else {
            handle.cancel()
            throw GoogleOAuth.AuthError.listenerFailed("could not bind a loopback port")
        }
        port = boundPort.value

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
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

/// A lock-guarded box so the port can cross from NWListener's queue back to
/// the initializer without tripping strict concurrency.
private final class PortBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: UInt16 = 0
    var value: UInt16 {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
