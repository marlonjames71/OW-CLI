import Darwin
import Foundation

/// A simple arrow-key-navigable selection menu rendered directly in the terminal.
///
/// Usage:
/// ```swift
/// if let choice = InteractiveSelector.select(from: ["Preview", "Skim"], prompt: "Select app for .pdf") {
///     print("Chose: \(choice)")
/// }
/// ```
enum InteractiveSelector {

    /// Presents an interactive list and returns the item the user selected,
    /// or `nil` if they pressed Escape or Ctrl-C.
    static func select(from items: [String], prompt: String) -> String? {
        guard !items.isEmpty else { return nil }

        // Always open /dev/tty directly so the picker works even when stdin
        // is a pipe (e.g. `find . -name Makefile | ow set`). /dev/tty is the
        // process's controlling terminal regardless of stdin/stdout redirection.
        let ttyFD = open("/dev/tty", O_RDWR)
        guard ttyFD >= 0 else { return nil }
        defer { close(ttyFD) }

        // Enter raw mode on the tty so we read individual keypresses.
        var original = termios()
        tcgetattr(ttyFD, &original)
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        tcsetattr(ttyFD, TCSANOW, &raw)

        hideCursor()

        defer {
            tcsetattr(ttyFD, TCSANOW, &original)
            showCursor()
        }

        var selected = 0
        printMenu(items: items, selected: selected, prompt: prompt)

        while true {
            switch readKey(from: ttyFD) {
            case .up where selected > 0:
                selected -= 1
                redrawMenu(items: items, selected: selected, prompt: prompt)
            case .down where selected < items.count - 1:
                selected += 1
                redrawMenu(items: items, selected: selected, prompt: prompt)
            case .enter:
                clearMenu(lineCount: menuLineCount(for: items))
                return items[selected]
            case .escape, .ctrlC:
                clearMenu(lineCount: menuLineCount(for: items))
                return nil
            default:
                break
            }
        }
    }

    // MARK: - Drawing

    private static func menuLineCount(for items: [String]) -> Int {
        // blank + prompt + blank + items + blank + hint = items.count + 5 newlines
        return items.count + 5
    }

    private static func printMenu(items: [String], selected: Int, prompt: String) {
        print("")
        print("  \(prompt):")
        print("")
        for (i, item) in items.enumerated() {
            if i == selected {
                print("  \u{1B}[36m\u{1B}[1m> \(item)\u{1B}[0m")
            } else {
                print("    \(item)")
            }
        }
        print("")
        print("  \u{1B}[2m\u{2191}\u{2193} to move  \u{00B7}  enter to select  \u{00B7}  esc to cancel\u{1B}[0m")
        fflush(stdout)
    }

    private static func redrawMenu(items: [String], selected: Int, prompt: String) {
        let lines = menuLineCount(for: items)
        print("\u{1B}[\(lines)A\u{1B}[0J", terminator: "")
        printMenu(items: items, selected: selected, prompt: prompt)
    }

    private static func clearMenu(lineCount: Int) {
        print("\u{1B}[\(lineCount)A\u{1B}[0J", terminator: "")
        fflush(stdout)
    }

    private static func hideCursor() {
        print("\u{1B}[?25l", terminator: "")
        fflush(stdout)
    }

    private static func showCursor() {
        print("\u{1B}[?25h", terminator: "")
        fflush(stdout)
    }

    // MARK: - Keyboard input

    private enum Key {
        case up, down, enter, escape, ctrlC, other
    }

    private static func readKey(from fd: Int32) -> Key {
        var byte: UInt8 = 0

        guard read(fd, &byte, 1) == 1 else { return .other }

        switch byte {
        case 13, 10:   return .enter   // Return (CR or LF — terminals may send either)
        case 3:        return .ctrlC   // Ctrl-C
        case 27:       break           // ESC or start of escape sequence
        default:       return .other
        }

        // Read the next two bytes non-blocking to distinguish a bare ESC
        // from an arrow-key escape sequence (ESC [ A/B).
        let savedFlags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, savedFlags | O_NONBLOCK)
        defer { _ = fcntl(fd, F_SETFL, savedFlags) }

        var seq = [UInt8](repeating: 0, count: 2)
        let n = read(fd, &seq, 2)

        guard n == 2, seq[0] == 91 else { return .escape }  // ESC [

        switch seq[1] {
        case 65: return .up    // ESC [ A
        case 66: return .down  // ESC [ B
        default: return .other
        }
    }
}
