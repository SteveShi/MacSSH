import Foundation

public struct Snippet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var command: String
    public var autoExecute: Bool
    public var category: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        command: String,
        autoExecute: Bool = true,
        category: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.autoExecute = autoExecute
        self.category = category
        self.createdAt = createdAt
    }
}
