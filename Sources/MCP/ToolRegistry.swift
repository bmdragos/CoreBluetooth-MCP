import Foundation

// MARK: - Tool Protocol

protocol Tool {
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: JSONValue] { get }

    func execute(arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String
}

// MARK: - Tool Error

struct ToolError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

// MARK: - Tool Registry

class ToolRegistry {
    private var tools: [String: Tool] = [:]

    func register(_ tool: Tool) {
        tools[tool.name] = tool
    }

    func listTools() -> [JSONValue] {
        tools.values.map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": .object(tool.inputSchema.mapValues { $0 })
            ])
        }
    }

    func callTool(name: String, arguments: [String: JSONValue], bleManager: BLEManager) async throws -> String {
        guard let tool = tools[name] else {
            throw ToolError("Unknown tool: \(name)")
        }
        return try await tool.execute(arguments: arguments, bleManager: bleManager)
    }
}
