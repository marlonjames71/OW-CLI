import ArgumentParser
import Darwin
import Foundation

struct Wow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wow",
        abstract: "Show a small OW surprise.",
        shouldDisplay: false
    )

    func run() throws {
        let useColor = isatty(STDOUT_FILENO) == 1
        print(render(useColor: useColor))
    }

    private func render(useColor: Bool) -> String {
        let blue = useColor ? "\u{1B}[33m" : ""
        let lightBlue = useColor ? "\u{1B}[92m" : ""
        let white = useColor ? "\u{1B}[97m" : ""
        let dim = useColor ? "\u{1B}[2m" : ""
        let bold = useColor ? "\u{1B}[1m" : ""
        let reset = useColor ? "\u{1B}[0m" : ""

        let logoArt = #"""
      0_
       \`.     ___
        \ \   / __>0
    /\  /  |/' /
   /  \/   `  ,`'--.
  / /(___________)_ \
  |/ //.-.   .-.\\ \ \
  0 // :@ ___ @: \\ \/
    ( o ^(___)^ o ) 0
     \ \_______/ /
 /\   '._______.'--.
 \ /|  |<_____>    |
  \ \__|<_____>____/|__
   \____<_____>_______/
       |<_____>    |
       |<_____>    |
       :<_____>____:
      / <_____>   /|
     /  <_____>  / |
    /___________/  |
    |           | _|__
    |           | ---||_
    |     OW    |  | [__]
    |           |  /
    |           | /
    |___________|/
"""#
        let logo = logoArt.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                let color = index < 20 ? lightBlue : blue
                return "\(color)\(line)\(reset)"
            }

        let info = [
            "\(bold)OW\(reset) \(dim)(Open With)\(reset)",
            "\(blue)----------------\(reset)",
            "\(white)mode\(reset)        default app manager",
            "\(white)scope\(reset)       extensions + per-file overrides",
            "\(white)index\(reset)       OW-created overrides",
            "\(white)quarantine\(reset)  warn | clear | ignore",
            "\(white)hint\(reset)        ow config",
        ]

        return zipColumns(left: logo, right: info, spacing: 4)
    }

    private func zipColumns(left: [String], right: [String], spacing: Int) -> String {
        let leftWidth = left.map(visibleLength).max() ?? 0
        let blank = String(repeating: " ", count: spacing)
        let rows = max(left.count, right.count)

        return (0..<rows).map { index in
            let leftText = index < left.count ? left[index] : ""
            let rightText = index < right.count ? right[index] : ""
            let padding = String(repeating: " ", count: max(0, leftWidth - visibleLength(leftText)))
            return leftText + padding + blank + rightText
        }
        .joined(separator: "\n")
    }

    private func visibleLength(_ string: String) -> Int {
        var count = 0
        var iterator = string.makeIterator()

        while let character = iterator.next() {
            guard character == "\u{1B}" else {
                count += 1
                continue
            }

            while let next = iterator.next(), next != "m" {}
        }

        return count
    }
}
