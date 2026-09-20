import AppKit

// MARK: - SpaceAnchor — pinning the notch to the hardware, not to a desktop
//
// THIS FILE USES PRIVATE APIS, deliberately and against the project's usual
// rule. What follows is why, and what was done to make that survivable.
//
// The public recipe — `.canJoinAllSpaces` + `.stationary` — is what Otto
// already had, and it does not hold: during a horizontal Spaces swipe AppKit
// re-parents the window with the transition, so a panel that is meant to be a
// hole in the hardware slides away with the desktop underneath it (Marcello,
// reported repeatedly through 2026-09). Raising the level to `.screenSaver`
// was tried and did not change it.
//
// Alcove solves it and solves it well, which is the comparison that settled
// this. Its binary imports thirteen `CGS*` symbols — `CGSMainConnectionID`,
// `CGSAddWindowsToSpaces`, `CGSCopyManagedDisplaySpaces`,
// `CGSSpaceSetAbsoluteLevel` among them. There is no public equivalent: the
// window server owns space membership, and AppKit's wrapper over it is the
// thing getting in the way. Marcello's call, made with the cost in front of
// him (2026-09-20).
//
// THE COST, AND THE MITIGATION. Linking an undocumented symbol directly means
// that the day Apple renames or removes it, dyld cannot resolve it and the app
// DOES NOT LAUNCH AT ALL — not "this feature stops working", the whole thing
// refuses to open, silently, for everyone who took a macOS update. So nothing
// here is linked. Every symbol is resolved at runtime with `dlsym`, and if any
// one of them is missing this type reports itself unavailable and the caller
// keeps AppKit's own behaviour. The worst case is the bug we have today.
//
// Nothing here touches data or privileges — these are window-management calls.
// They need no entitlement, and notarization does not inspect for them, so the
// signing and update pipeline is unaffected.

@MainActor
enum SpaceAnchor {

    // MARK: The symbols
    //
    // Resolved once. `CGSMainConnectionID` and `CGSAddWindowsToSpaces` are the
    // only two this needs — Alcove imports eleven more for features Otto does
    // not have (creating and destroying spaces, hiding them). Borrowing the
    // smallest possible surface is the difference between one call to re-check
    // after a macOS update and thirteen.

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias AddWindowsToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void

    private static let handle: UnsafeMutableRawPointer? = {
        // The symbols live in CoreGraphics, which is already loaded — this is
        // a lookup in the running process, not a load of anything new.
        dlopen(nil, RTLD_LAZY)
    }()

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let mainConnectionID = symbol("CGSMainConnectionID", as: MainConnectionID.self)
    private static let copySpaces = symbol("CGSCopyManagedDisplaySpaces",
                                           as: CopyManagedDisplaySpaces.self)
    private static let addWindows = symbol("CGSAddWindowsToSpaces", as: AddWindowsToSpaces.self)

    /// True when every symbol resolved. When false the caller must keep doing
    /// whatever it did before — this type will not half-work.
    static var isAvailable: Bool {
        mainConnectionID != nil && copySpaces != nil && addWindows != nil
    }

    // MARK: Pinning

    /// Put `window` on EVERY space, at the window-server level.
    ///
    /// The difference from `.canJoinAllSpaces` is who does it. That flag asks
    /// AppKit to present the window on each space, and AppKit carries it
    /// across during the transition — which is the slide. Adding it to every
    /// space directly means it is genuinely resident on all of them at once,
    /// so a swipe has nothing to carry: the desktops move and the window does
    /// not, because it was never on the one that left.
    ///
    /// Returns false if anything was unavailable, so the caller can fall back.
    @discardableResult
    static func pinToAllSpaces(_ window: NSWindow) -> Bool {
        guard let mainConnectionID, let copySpaces, let addWindows else { return false }
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else { return false }

        let connection = mainConnectionID()
        guard let displays = copySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }

        // The shape is one entry per DISPLAY, each holding that display's
        // spaces. Flattened, because the notch belongs to the hardware and the
        // hardware does not care which display's desktop you swiped to.
        var spaceIDs: [NSNumber] = []
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                // Fullscreen spaces report their id under the same key; there
                // is nothing to filter out, and filtering would put the notch
                // back to being absent exactly where it is wanted most.
                if let id = space["id64"] as? NSNumber {
                    spaceIDs.append(id)
                } else if let id = space["ManagedSpaceID"] as? NSNumber {
                    spaceIDs.append(id)
                }
            }
        }
        guard !spaceIDs.isEmpty else { return false }

        addWindows(connection,
                   [NSNumber(value: windowNumber)] as CFArray,
                   spaceIDs as CFArray)
        lastPinnedSpaceCount = spaceIDs.count
        return true
    }

    /// How many spaces the last pin covered. Diagnostics only — a boolean
    /// "it worked" cannot tell a real pin from one that found no spaces.
    private(set) static var lastPinnedSpaceCount = 0
}
