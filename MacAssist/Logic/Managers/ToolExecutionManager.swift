
import Combine
import Foundation

class ToolExecutionManager {
    private let tools: [any ToolProtocol]
    
    init(tools: [any ToolProtocol]) {
        self.tools = tools
    }
    
    func executeTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let tool = tools.first(where: { $0.name == name }) else {
            throw NSError(domain: "ToolExecutionManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Tool not found"])
        }
        
        return try await tool.execute(arguments: arguments)
    }
}
