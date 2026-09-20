import AppKit

// MARK: - SpaceAnchor — a space of our own, which no desktop can carry away
//
// THIS FILE USES PRIVATE APIS, deliberately, against the project's usual rule
// and with Marcello's decision on the record (2026-09-20). What follows is the
// technique, why the public one cannot work, and what makes this survivable.
//
// THE PUBLIC RECIPE CANNOT DO IT. `.canJoinAllSpaces` + `.stationary` asks
// AppKit to present the window on every space, and AppKit carries it across
// during a swipe — the carrying IS the bug. `.screenSaver` level did not change
// it. Neither did adding the window to every existing space by hand: a window
// that is a member of the space being animated animates with it, however many
// other spaces it is also in. That was the first attempt here and it failed for
// a reason worth keeping: membership is not the same as residence.
//
// WHAT ALCOVE DOES, and it is the whole trick: it does not join the desktops'
// spaces at all. It CREATES ONE OF ITS OWN, sets that space's absolute level
// above them, shows it permanently, and puts its window in it. A window living
// in a space that belongs to no desktop is not part of any desktop's transition
// — the desktops slide underneath and it does not move, because it was never
// standing on one. Its binary imports exactly the symbols that spell this out:
// CGSSpaceCreate, CGSSpaceSetAbsoluteLevel, CGSShowSpaces, CGSAddWindowsToSpaces.
//
// The first version of this file borrowed only three symbols and called that
// prudence. It left out the mechanism — which is how it shipped a pin that did
// nothing (Marcello's screenshot, two notches mid-swipe).
//
// NOTHING IS LINKED. Every symbol is resolved with `dlsym` at runtime. Linking
// an undocumented symbol means that the day Apple renames it, dyld cannot
// resolve it and the app DOES NOT LAUNCH — not "the feature stops", the whole
// thing refuses to open, silently, for everyone who took an OS update. Resolved
// at runtime, a missing symbol makes `isAvailable` false and the caller keeps
// AppKit's behaviour: the notch travels, which is an annoyance rather than a
// brick.

@MainActor
enum SpaceAnchor {

    // MARK: Types
    //
    // CGSSpaceID is 64-bit. Getting this width wrong is not a compile error and
    // not a nil — it is a call into the window server with a mangled argument,
    // so it is stated once here rather than spelled out at each use.

    private typealias CGSSpaceID = UInt64
    private typealias ConnectionID = Int32

    private typealias FnMainConnection = @convention(c) () -> ConnectionID
    private typealias FnSpaceCreate = @convention(c) (ConnectionID, UnsafeMutableRawPointer?, CFDictionary?) -> CGSSpaceID
    private typealias FnSpaceSetAbsoluteLevel = @convention(c) (ConnectionID, CGSSpaceID, Int32) -> Void
    private typealias FnShowSpaces = @convention(c) (ConnectionID, CFArray) -> Void
    private typealias FnHideSpaces = @convention(c) (ConnectionID, CFArray) -> Void
    private typealias FnSpaceDestroy = @convention(c) (ConnectionID, CGSSpaceID) -> Void
    private typealias FnAddWindowsToSpaces = @convention(c) (ConnectionID, CFArray, CFArray) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(nil, RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let mainConnection = symbol("CGSMainConnectionID", as: FnMainConnection.self)
    private static let spaceCreate = symbol("CGSSpaceCreate", as: FnSpaceCreate.self)
    private static let spaceSetAbsoluteLevel = symbol("CGSSpaceSetAbsoluteLevel",
                                                      as: FnSpaceSetAbsoluteLevel.self)
    private static let showSpaces = symbol("CGSShowSpaces", as: FnShowSpaces.self)
    private static let hideSpaces = symbol("CGSHideSpaces", as: FnHideSpaces.self)
    private static let spaceDestroy = symbol("CGSSpaceDestroy", as: FnSpaceDestroy.self)
    private static let addWindows = symbol("CGSAddWindowsToSpaces", as: FnAddWindowsToSpaces.self)

    /// Every symbol the technique needs. All or nothing — a half-resolved
    /// version of this would make a space and fail to show it, which is worse
    /// than not trying.
    static var isAvailable: Bool {
        mainConnection != nil && spaceCreate != nil && spaceSetAbsoluteLevel != nil
            && showSpaces != nil && addWindows != nil
    }

    // MARK: State

    private static var space: CGSSpaceID?
    private(set) static var lastError: String?

    // MARK: Pinning

    /// Move `window` into a space of Otto's own, above the desktops.
    ///
    /// Idempotent: the space is made once and reused. Called again after the
    /// window is re-ordered or the displays change, because a window loses its
    /// space membership when its window number changes.
    @discardableResult
    static func pin(_ window: NSWindow) -> Bool {
        guard let mainConnection, let spaceCreate, let spaceSetAbsoluteLevel,
              let showSpaces, let addWindows else {
            lastError = "symbols unavailable"
            return false
        }
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else {
            lastError = "window not on screen yet"
            return false
        }

        let connection = mainConnection()

        let target: CGSSpaceID
        if let existing = space {
            target = existing
        } else {
            // The second argument is documented nowhere and is NULL in every
            // known use; the options dictionary is likewise empty.
            let created = spaceCreate(connection, nil, nil)
            guard created != 0 else {
                lastError = "CGSSpaceCreate returned 0"
                return false
            }
            space = created
            target = created

            // ABOVE the desktops. This is the line that makes the swipe leave
            // it alone: a space with an absolute level of its own is not part
            // of the row of desktops the gesture scrolls through.
            spaceSetAbsoluteLevel(connection, target, Int32(CGShieldingWindowLevel()))
            // And permanently visible, or the window inside it is on a space
            // nobody is looking at.
            showSpaces(connection, [NSNumber(value: target)] as CFArray)
        }

        addWindows(connection,
                   [NSNumber(value: windowNumber)] as CFArray,
                   [NSNumber(value: target)] as CFArray)
        lastError = nil
        return true
    }

    /// Give the space back. Not strictly required — the window server cleans up
    /// when the process dies — but a space left showing after a crash-free quit
    /// is litter in someone else's Mission Control.
    static func release() {
        guard let mainConnection, let space else { return }
        let connection = mainConnection()
        hideSpaces?(connection, [NSNumber(value: space)] as CFArray)
        spaceDestroy?(connection, space)
        self.space = nil
    }

    /// Diagnostics for the runtime probe: a boolean cannot tell a real pin from
    /// one that quietly did nothing.
    static var debugDescription: String {
        "available=\(isAvailable) space=\(space.map(String.init) ?? "nil") "
            + "shieldLevel=\(CGShieldingWindowLevel()) error=\(lastError ?? "none")"
    }
}
