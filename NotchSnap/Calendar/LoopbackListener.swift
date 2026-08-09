import Darwin
import Foundation

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
//
// BUILT ON RAW POSIX SOCKETS, NOT Network.framework — this is the second
// implementation, and that switch is the actual fix, not a stylistic choice.
//
// The first version used NWListener with `requiredInterfaceType = .loopback`,
// which threw "NWError 22 - Invalid argument" on every attempt
// (Marcello, 2026-08-09) — and had been doing so since the very first release
// with Google sign-in; the ORIGINAL code discarded the listener's
// `.failed(error)` payload and reported a generic "could not bind" message
// regardless of cause, so the real error was never visible until that
// swallowing was fixed first. The second attempt swapped in
// `requiredLocalEndpoint` pinned to 127.0.0.1 instead — the documented
// listener-appropriate alternative — and it failed with the IDENTICAL error.
//
// Standalone testing (swiftc, no app, no signing) isolated why: EVERY
// NWListener configuration failed with the same EINVAL, including one with
// zero parameters set at all — while a plain POSIX `socket()`/`bind()`/
// `listen()` on the exact same loopback address succeeded immediately, from
// both Python and Swift. Network.framework's listener path runs through
// Apple's NECP (Network Extension Control Policy) subsystem, which plain BSD
// sockets never touch — and something about NECP client registration is
// unavailable in at least one real execution context, ad-hoc signing making
// no difference. Rather than gamble on a third Network.framework variant
// against an API surface that has now failed two different ways for reasons
// neither attempt could actually observe, this drops NECP entirely for a job
// that never needed its extra machinery: bind, listen, accept one connection,
// read one request, respond, close.
//
// Bonus: bind()/listen() are synchronous syscalls, not an async state machine
// waiting on a `.ready` callback — the whole "how long do we wait, and on
// which thread" question that produced the ORIGINAL main-actor-blocking bug
// no longer exists. `create()` stays `async throws` only so GoogleOAuth's
// call site didn't need to change.

final class LoopbackListener: @unchecked Sendable {
    let port: UInt16

    private let fd: Int32
    private let queue = DispatchQueue(label: "com.notchsnap.oauth.loopback")
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private var stopped = false
    private let lock = NSLock()

    static func create() async throws -> LoopbackListener {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw GoogleOAuth.AuthError.listenerFailed(
                "could not create a socket (\(String(cString: strerror(errno))))")
        }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // ask the kernel for a free ephemeral port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")  // loopback ONLY, never 0.0.0.0

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(socketFD)
            throw GoogleOAuth.AuthError.listenerFailed("could not bind a loopback port (\(message))")
        }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &len)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(socketFD)
            throw GoogleOAuth.AuthError.listenerFailed("could not read back the bound port")
        }
        let boundPort = UInt16(bigEndian: boundAddr.sin_port)
        guard boundPort != 0 else {
            Darwin.close(socketFD)
            throw GoogleOAuth.AuthError.listenerFailed("kernel returned port 0")
        }

        guard listen(socketFD, 4) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(socketFD)
            throw GoogleOAuth.AuthError.listenerFailed("could not listen on the loopback port (\(message))")
        }

        let result = LoopbackListener(fd: socketFD, port: boundPort)
        result.acceptLoop()
        return result
    }

    private init(fd: Int32, port: UInt16) {
        self.fd = fd
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
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        lock.unlock()
        // shutdown() before close(): the reliable way to unblock a thread
        // parked in accept() on this fd from another thread, rather than
        // relying on close() alone to do it.
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }

    // MARK: Plumbing

    /// One blocking `accept()` loop on its own queue. Not Network.framework's
    /// per-connection callback model, but the same effect: each real
    /// connection is handled in turn, and closing `fd` from `stop()` is what
    /// ends the loop (`accept()` returns -1 once the fd is gone).
    private func acceptLoop() {
        queue.async { [weak self] in
            while let self {
                var clientAddr = sockaddr()
                var clientLen = socklen_t(MemoryLayout<sockaddr>.size)
                let clientFD = accept(self.fd, &clientAddr, &clientLen)
                guard clientFD >= 0 else { return }  // fd closed via stop(), or a real error either way
                self.handle(clientFD)
            }
        }
    }

    private func handle(_ clientFD: Int32) {
        defer { Darwin.close(clientFD) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        let received = recv(clientFD, &buffer, buffer.count, 0)
        guard received > 0 else { return }
        let request = String(bytes: buffer[0..<received], encoding: .utf8) ?? ""
        let result = Self.parse(requestLine: request)

        let success: Bool
        if case .success = result { success = true } else { success = false }
        let body = Self.responsePage(success: success)
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        _ = response.withCString { send(clientFD, $0, strlen($0), 0) }
        finish(result)
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
