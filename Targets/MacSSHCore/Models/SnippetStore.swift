import Foundation

public enum SnippetStore {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacSSH", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.json")
    }

    public static func load() -> [Snippet] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return defaultSnippets()
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snippets = try decoder.decode([Snippet].self, from: data)
            return snippets.isEmpty ? defaultSnippets() : snippets
        } catch {
            return defaultSnippets()
        }
    }

    public static func save(_ snippets: [Snippet]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snippets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func defaultSnippets() -> [Snippet] {
        [
            Snippet(title: "Docker 容器状态", command: "docker ps -a", autoExecute: true, category: "Docker"),
            Snippet(title: "实时系统监控 (htop)", command: "htop", autoExecute: true, category: "系统"),
            Snippet(title: "查看磁盘空间", command: "df -h", autoExecute: true, category: "系统"),
            Snippet(title: "查看内存占用", command: "free -h", autoExecute: true, category: "系统"),
            Snippet(title: "查看系统日志", command: "journalctl -xe -n 50", autoExecute: true, category: "排查"),
            Snippet(title: "查看开放端口", command: "ss -tulpn", autoExecute: true, category: "网络"),
            Snippet(title: "Git 状态与最近提交", command: "git status && git log -n 5 --oneline", autoExecute: true, category: "Git")
        ]
    }
}
