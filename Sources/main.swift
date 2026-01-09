import Foundation
import CoreBluetooth

// Entry point - run the MCP server
let server = MCPServer()

// We need a RunLoop for CoreBluetooth callbacks
// Run the server in a Task and keep the RunLoop alive
Task {
    await server.run()
    exit(0)
}

RunLoop.main.run()
