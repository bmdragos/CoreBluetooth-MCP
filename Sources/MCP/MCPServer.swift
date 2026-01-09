import Foundation

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: RequestID?
    let method: String
    let params: JSONValue?

    enum RequestID: Codable, Equatable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
            } else if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else {
                throw DecodingError.typeMismatch(RequestID.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Int"))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            }
        }
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCRequest.RequestID?
    let result: JSONValue?
    let error: JSONRPCError?

    init(id: JSONRPCRequest.RequestID?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONRPCRequest.RequestID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: JSONValue?

    static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)", data: nil)
    }

    static func invalidParams(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: msg, data: nil)
    }

    static func internalError(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: msg, data: nil)
    }
}

// MARK: - JSON Value (for dynamic params/results)

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown JSON type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let obj) = self { return obj }
        return nil
    }

    subscript(_ key: String) -> JSONValue? {
        if case .object(let obj) = self { return obj[key] }
        return nil
    }
}

// MARK: - MCP Server

actor MCPServer {
    private let bleManager = BLEManager()
    private let toolRegistry: ToolRegistry
    private var notificationQueue: [JSONValue] = []

    init() {
        self.toolRegistry = ToolRegistry()
    }

    func run() async {
        // Set up tool handlers
        await registerTools()

        // Start BLE manager
        await bleManager.start()

        // Process stdin line by line
        let stdin = FileHandle.standardInput
        var buffer = Data()

        while true {
            let data = stdin.availableData
            if data.isEmpty {
                // EOF - exit gracefully
                break
            }
            buffer.append(data)

            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[..<newlineIndex]
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    await processLine(line)
                }
            }
        }
    }

    private func processLine(_ line: String) async {
        guard let data = line.data(using: .utf8) else { return }

        do {
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
            let response = await handleRequest(request)
            sendResponse(response)
        } catch {
            let errorResponse = JSONRPCResponse(id: nil, error: .internalError("Parse error: \(error.localizedDescription)"))
            sendResponse(errorResponse)
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return JSONRPCResponse(id: request.id, result: .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([
                    "tools": .object([:])
                ]),
                "serverInfo": .object([
                    "name": .string("ble-mcp"),
                    "version": .string("1.0.0")
                ])
            ]))

        case "notifications/initialized":
            // Client acknowledged initialization
            return JSONRPCResponse(id: request.id, result: .object([:]))

        case "tools/list":
            let tools = toolRegistry.listTools()
            return JSONRPCResponse(id: request.id, result: .object([
                "tools": .array(tools)
            ]))

        case "tools/call":
            guard let params = request.params?.objectValue,
                  let name = params["name"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: .invalidParams("Missing tool name"))
            }
            let arguments = params["arguments"]?.objectValue ?? [:]

            do {
                let result = try await toolRegistry.callTool(name: name, arguments: arguments, bleManager: bleManager)
                return JSONRPCResponse(id: request.id, result: .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(result)
                        ])
                    ])
                ]))
            } catch let error as ToolError {
                return JSONRPCResponse(id: request.id, result: .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string("Error: \(error.message)")
                        ])
                    ]),
                    "isError": .bool(true)
                ]))
            } catch {
                return JSONRPCResponse(id: request.id, result: .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string("Error: \(error.localizedDescription)")
                        ])
                    ]),
                    "isError": .bool(true)
                ]))
            }

        default:
            return JSONRPCResponse(id: request.id, error: .methodNotFound(request.method))
        }
    }

    private func sendResponse(_ response: JSONRPCResponse) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(response),
           let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
            fflush(stdout)
        }
    }

    private func registerTools() async {
        // Core BLE tools
        toolRegistry.register(BleScanTool())
        toolRegistry.register(BleConnectTool())
        toolRegistry.register(BleDisconnectTool())
        toolRegistry.register(BleStatusTool())
        toolRegistry.register(BleServicesTool())
        toolRegistry.register(BleCharacteristicsTool())
        toolRegistry.register(BleReadTool())
        toolRegistry.register(BleWriteTool())
        toolRegistry.register(BleSubscribeTool())
        toolRegistry.register(BleUnsubscribeTool())

        // FTMS Discovery
        toolRegistry.register(FtmsDiscoverTool())
        toolRegistry.register(FtmsInfoTool())

        // FTMS Data
        toolRegistry.register(FtmsReadTool())
        toolRegistry.register(FtmsSubscribeTool())
        toolRegistry.register(FtmsUnsubscribeTool())

        // FTMS Control
        toolRegistry.register(FtmsRequestControlTool())
        toolRegistry.register(FtmsSetPowerTool())
        toolRegistry.register(FtmsResetTool())
        toolRegistry.register(FtmsStartTool())
        toolRegistry.register(FtmsStopTool())

        // Debugging
        toolRegistry.register(FtmsRawReadTool())
        toolRegistry.register(FtmsRawWriteTool())
        toolRegistry.register(FtmsLogStartTool())
        toolRegistry.register(FtmsLogStopTool())

        // Nice to have
        toolRegistry.register(FtmsMonitorTool())
        toolRegistry.register(FtmsTestSequenceTool())
    }
}
