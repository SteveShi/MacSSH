import Foundation

/// Headless VT100/ANSI screen state machine that turns a session's raw PTY replay buffer
/// into plain screen text, full scrollback, or the last command's output (via OSC 133 marks).
public final class ScreenRenderer {
    private static let spacer: Character = "\u{0}"
    private static let scrollbackLineLimit = 20000

    private let columns: Int
    private let rows: Int
    private var screen: [[Character]]
    private var scrollback: [[Character]] = []
    private var cursorRow = 0
    private var cursorColumn = 0
    private var savedCursor = (row: 0, column: 0)
    private var scrollTop: Int
    private var scrollBottom: Int
    private var autoWrap = true
    private var wrapPending = false
    private var savedAlt: (screen: [[Character]], cursor: (row: Int, column: Int))?
    private var outputStartRow: Int?
    private var promptStartRow: Int?
    private var scrolledOffRows = 0

    private enum State {
        case ground
        case escape
        case csi
        case osc
        case ignoredString
        case stringEscape
        case charset
    }

    private var state: State = .ground
    private var controlSequence: [UInt8] = []
    private var oscBuffer: [UInt8] = []
    private var pendingScalar: [UInt8] = []
    private var pendingScalarLength = 0

    public init(columns: UInt16, rows: UInt16) {
        self.columns = max(1, Int(columns))
        self.rows = max(1, Int(rows))
        self.screen = Array(repeating: Array(repeating: " ", count: self.columns), count: self.rows)
        self.scrollTop = 0
        self.scrollBottom = self.rows - 1
    }

    public func feed(_ data: Data) {
        for byte in data {
            consume(byte)
        }
    }

    public func render(includeScrollback: Bool = false, lastCommandOnly: Bool = false) -> String {
        let allRows: [[Character]]
        if lastCommandOnly, let start = outputStartRow {
            let combined = scrollback + screen
            let startIdx = max(0, start - scrolledOffRows)
            let endIdx: Int
            if let prompt = promptStartRow, prompt >= start {
                endIdx = min(combined.count, max(startIdx, prompt - scrolledOffRows))
            } else {
                endIdx = combined.count
            }
            allRows = Array(combined[startIdx..<endIdx])
        } else if includeScrollback {
            allRows = scrollback + screen
        } else {
            allRows = screen
        }

        var lines = allRows.map { row -> String in
            var s = String(row.filter { $0 != Self.spacer })
            while s.last == " " {
                s.removeLast()
            }
            return s
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private func consume(_ byte: UInt8) {
        if byte == 0x1B {
            pendingScalar.removeAll(keepingCapacity: true)
            pendingScalarLength = 0
            if state == .osc || state == .ignoredString {
                state = .stringEscape
            } else {
                state = .escape
            }
            return
        }

        switch state {
        case .ground:
            consumeGround(byte)
        case .escape:
            consumeEscape(byte)
        case .csi:
            consumeCSI(byte)
        case .osc:
            if byte == 0x07 {
                finishOSC()
                state = .ground
            } else if oscBuffer.count < 64 {
                oscBuffer.append(byte)
            }
        case .ignoredString:
            if byte == 0x07 {
                state = .ground
            }
        case .stringEscape:
            if byte == 0x5C { // '\'
                finishOSC()
                state = .ground
            } else {
                state = .escape
                consumeEscape(byte)
            }
        case .charset:
            state = .ground
        }
    }

    private func finishOSC() {
        defer { oscBuffer.removeAll(keepingCapacity: true) }
        guard let str = String(bytes: oscBuffer, encoding: .utf8) else { return }
        let absRow = scrolledOffRows + scrollback.count + cursorRow
        if str.hasPrefix("133;C") {
            outputStartRow = absRow
        } else if str.hasPrefix("133;A") {
            promptStartRow = absRow
        }
    }

    private func consumeGround(_ byte: UInt8) {
        switch byte {
        case 0x00...0x06, 0x0B...0x0C, 0x0E...0x1A, 0x1C...0x1F, 0x7F:
            return
        case 0x07: // BEL
            return
        case 0x08: // BS
            wrapPending = false
            if cursorColumn > 0 { cursorColumn -= 1 }
        case 0x09: // TAB
            wrapPending = false
            let nextTab = ((cursorColumn / 8) + 1) * 8
            cursorColumn = min(columns - 1, nextTab)
        case 0x0A: // LF
            wrapPending = false
            lineFeed()
        case 0x0D: // CR
            wrapPending = false
            cursorColumn = 0
        default:
            consumeUTF8(byte)
        }
    }

    private func consumeUTF8(_ byte: UInt8) {
        if pendingScalarLength == 0 {
            if byte < 0x80 {
                putCharacter(Character(UnicodeScalar(byte)))
            } else if (byte & 0xE0) == 0xC0 {
                pendingScalar = [byte]
                pendingScalarLength = 2
            } else if (byte & 0xF0) == 0xE0 {
                pendingScalar = [byte]
                pendingScalarLength = 3
            } else if (byte & 0xF8) == 0xF0 {
                pendingScalar = [byte]
                pendingScalarLength = 4
            }
        } else {
            if (byte & 0xC0) == 0x80 {
                pendingScalar.append(byte)
                if pendingScalar.count == pendingScalarLength {
                    if let str = String(bytes: pendingScalar, encoding: .utf8), let ch = str.first {
                        putCharacter(ch)
                    }
                    pendingScalar.removeAll(keepingCapacity: true)
                    pendingScalarLength = 0
                }
            } else {
                pendingScalar.removeAll(keepingCapacity: true)
                pendingScalarLength = 0
                consumeUTF8(byte)
            }
        }
    }

    private func putCharacter(_ ch: Character) {
        let width = Self.displayWidth(of: ch)
        guard width > 0 else { return }

        if wrapPending {
            wrapPending = false
            cursorColumn = 0
            lineFeed()
        }

        if width == 2 && cursorColumn == columns - 1 {
            screen[cursorRow][cursorColumn] = " "
            if autoWrap {
                cursorColumn = 0
                lineFeed()
            }
        }

        clearCell(row: cursorRow, col: cursorColumn)
        screen[cursorRow][cursorColumn] = ch
        if width == 2 && cursorColumn + 1 < columns {
            clearCell(row: cursorRow, col: cursorColumn + 1)
            screen[cursorRow][cursorColumn + 1] = Self.spacer
        }

        let nextCol = cursorColumn + width
        if nextCol >= columns {
            cursorColumn = columns - 1
            wrapPending = autoWrap
        } else {
            cursorColumn = nextCol
        }
    }

    private func clearCell(row: Int, col: Int) {
        guard row >= 0, row < rows, col >= 0, col < columns else { return }
        if screen[row][col] == Self.spacer, col > 0 {
            screen[row][col - 1] = " "
        } else if col + 1 < columns, screen[row][col + 1] == Self.spacer {
            screen[row][col + 1] = " "
        }
        screen[row][col] = " "
    }

    private func lineFeed() {
        if cursorRow == scrollBottom {
            scrollUp(count: 1)
        } else if cursorRow + 1 < rows {
            cursorRow += 1
        }
    }

    private func scrollUp(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            let removed = screen.remove(at: scrollTop)
            if scrollTop == 0 && savedAlt == nil {
                scrollback.append(removed)
                if scrollback.count > Self.scrollbackLineLimit {
                    scrollback.removeFirst()
                    scrolledOffRows += 1
                }
            }
            screen.insert(Array(repeating: " ", count: columns), at: scrollBottom)
        }
    }

    private func scrollDown(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            screen.remove(at: scrollBottom)
            screen.insert(Array(repeating: " ", count: columns), at: scrollTop)
        }
    }

    private func consumeEscape(_ byte: UInt8) {
        switch byte {
        case 0x5B: // '[' -> CSI
            controlSequence.removeAll(keepingCapacity: true)
            state = .csi
        case 0x5D: // ']' -> OSC
            oscBuffer.removeAll(keepingCapacity: true)
            state = .osc
        case 0x50, 0x58, 0x5E, 0x5F: // DCS, SOS, PM, APC
            state = .ignoredString
        case 0x28, 0x29, 0x2A, 0x2B: // '(' ')' '*' '+'
            state = .charset
        case 0x37: // '7' DECSC
            savedCursor = (cursorRow, cursorColumn)
            state = .ground
        case 0x38: // '8' DECRC
            cursorRow = min(rows - 1, max(0, savedCursor.row))
            cursorColumn = min(columns - 1, max(0, savedCursor.column))
            wrapPending = false
            state = .ground
        case 0x44: // 'D' IND
            wrapPending = false
            lineFeed()
            state = .ground
        case 0x45: // 'E' NEL
            wrapPending = false
            cursorColumn = 0
            lineFeed()
            state = .ground
        case 0x4D: // 'M' RI
            wrapPending = false
            if cursorRow == scrollTop {
                scrollDown(count: 1)
            } else if cursorRow > 0 {
                cursorRow -= 1
            }
            state = .ground
        case 0x63: // 'c' RIS
            screen = Array(repeating: Array(repeating: " ", count: columns), count: rows)
            cursorRow = 0
            cursorColumn = 0
            scrollTop = 0
            scrollBottom = rows - 1
            wrapPending = false
            state = .ground
        default:
            state = .ground
        }
    }

    private func consumeCSI(_ byte: UInt8) {
        if byte >= 0x20 && byte <= 0x3F {
            if controlSequence.count < 64 {
                controlSequence.append(byte)
            }
            return
        }
        guard byte >= 0x40 && byte <= 0x7E else {
            state = .ground
            return
        }
        handleCSI(finalByte: byte)
        state = .ground
    }

    private func handleCSI(finalByte: UInt8) {
        let paramStr = String(bytes: controlSequence, encoding: .ascii) ?? ""
        let isPrivate = paramStr.hasPrefix("?")
        let cleanParams = isPrivate ? String(paramStr.dropFirst()) : paramStr
        let parts = cleanParams.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let p0 = parts.first ?? 0
        let p1 = parts.count > 1 ? parts[1] : 0

        switch finalByte {
        case 0x41: // 'A' CUU
            wrapPending = false
            cursorRow = max(0, cursorRow - max(1, p0))
        case 0x42: // 'B' CUD
            wrapPending = false
            cursorRow = min(rows - 1, cursorRow + max(1, p0))
        case 0x43: // 'C' CUF
            wrapPending = false
            cursorColumn = min(columns - 1, cursorColumn + max(1, p0))
        case 0x44: // 'D' CUB
            wrapPending = false
            cursorColumn = max(0, cursorColumn - max(1, p0))
        case 0x45: // 'E' CNL
            wrapPending = false
            cursorColumn = 0
            cursorRow = min(rows - 1, cursorRow + max(1, p0))
        case 0x46: // 'F' CPL
            wrapPending = false
            cursorColumn = 0
            cursorRow = max(0, cursorRow - max(1, p0))
        case 0x47: // 'G' CHA
            wrapPending = false
            cursorColumn = min(columns - 1, max(0, max(1, p0) - 1))
        case 0x48, 0x66: // 'H', 'f' CUP
            wrapPending = false
            cursorRow = min(rows - 1, max(0, max(1, p0) - 1))
            cursorColumn = min(columns - 1, max(0, max(1, p1) - 1))
        case 0x4A: // 'J' ED
            wrapPending = false
            eraseInDisplay(mode: p0)
        case 0x4B: // 'K' EL
            wrapPending = false
            eraseInLine(mode: p0)
        case 0x4C: // 'L' IL
            wrapPending = false
            guard cursorRow >= scrollTop && cursorRow <= scrollBottom else { break }
            let count = min(max(1, p0), scrollBottom - cursorRow + 1)
            for _ in 0..<count {
                screen.remove(at: scrollBottom)
                screen.insert(Array(repeating: " ", count: columns), at: cursorRow)
            }
        case 0x4D: // 'M' DL
            wrapPending = false
            guard cursorRow >= scrollTop && cursorRow <= scrollBottom else { break }
            let count = min(max(1, p0), scrollBottom - cursorRow + 1)
            for _ in 0..<count {
                screen.remove(at: cursorRow)
                screen.insert(Array(repeating: " ", count: columns), at: scrollBottom)
            }
        case 0x50: // 'P' DCH
            wrapPending = false
            let count = min(max(1, p0), columns - cursorColumn)
            for _ in 0..<count {
                screen[cursorRow].remove(at: cursorColumn)
                screen[cursorRow].append(" ")
            }
        case 0x53: // 'S' SU
            scrollUp(count: max(1, p0))
        case 0x54: // 'T' SD
            scrollDown(count: max(1, p0))
        case 0x58: // 'X' ECH
            let count = min(max(1, p0), columns - cursorColumn)
            for i in 0..<count {
                clearCell(row: cursorRow, col: cursorColumn + i)
            }
        case 0x64: // 'd' VPA
            wrapPending = false
            cursorRow = min(rows - 1, max(0, max(1, p0) - 1))
        case 0x68: // 'h' SM / DECSET
            if isPrivate {
                for mode in parts {
                    if mode == 7 { autoWrap = true }
                    if mode == 47 || mode == 1047 || mode == 1049 {
                        if savedAlt == nil {
                            savedAlt = (screen: screen, cursor: (cursorRow, cursorColumn))
                            screen = Array(repeating: Array(repeating: " ", count: columns), count: rows)
                            if mode == 1049 {
                                cursorRow = 0
                                cursorColumn = 0
                            }
                        }
                    }
                }
            }
        case 0x6C: // 'l' RM / DECRST
            if isPrivate {
                for mode in parts {
                    if mode == 7 { autoWrap = false }
                    if mode == 47 || mode == 1047 || mode == 1049 {
                        if let alt = savedAlt {
                            screen = alt.screen
                            cursorRow = alt.cursor.row
                            cursorColumn = alt.cursor.column
                            savedAlt = nil
                        }
                    }
                }
            }
        case 0x72: // 'r' DECSTBM
            let top = max(1, p0) - 1
            let bottom = (p1 == 0 ? rows : p1) - 1
            if top < bottom && bottom < rows {
                scrollTop = top
                scrollBottom = bottom
                cursorRow = 0
                cursorColumn = 0
                wrapPending = false
            }
        default:
            break
        }
    }

    private func eraseInDisplay(mode: Int) {
        switch mode {
        case 0:
            eraseInLine(mode: 0)
            for r in (cursorRow + 1)..<rows {
                screen[r] = Array(repeating: " ", count: columns)
            }
        case 1:
            for r in 0..<cursorRow {
                screen[r] = Array(repeating: " ", count: columns)
            }
            eraseInLine(mode: 1)
        case 2, 3:
            screen = Array(repeating: Array(repeating: " ", count: columns), count: rows)
            if mode == 3 {
                scrollback.removeAll()
            }
        default:
            break
        }
    }

    private func eraseInLine(mode: Int) {
        switch mode {
        case 0:
            for c in cursorColumn..<columns {
                clearCell(row: cursorRow, col: c)
            }
        case 1:
            for c in 0...cursorColumn {
                clearCell(row: cursorRow, col: c)
            }
        case 2:
            screen[cursorRow] = Array(repeating: " ", count: columns)
        default:
            break
        }
    }

    private static func displayWidth(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        let v = scalar.value
        if v < 0x20 || (v >= 0x7F && v < 0xA0) { return 0 }
        if (0x0300...0x036F).contains(v) || (0x1AB0...0x1AFF).contains(v) ||
           (0x1DC0...0x1DFF).contains(v) || (0x20D0...0x20FF).contains(v) ||
           (0xFE20...0xFE2F).contains(v) {
            return 0
        }
        if (0x1100...0x115F).contains(v) ||
           (0x2E80...0xA4CF).contains(v) ||
           (0xAC00...0xD7A3).contains(v) ||
           (0xF900...0xFAFF).contains(v) ||
           (0xFE10...0xFE19).contains(v) ||
           (0xFE30...0xFE6F).contains(v) ||
           (0xFF00...0xFF60).contains(v) ||
           (0xFFE0...0xFFE6).contains(v) ||
           (0x1F300...0x1F9FF).contains(v) ||
           (0x20000...0x3FFFD).contains(v) {
            return 2
        }
        return 1
    }
}
