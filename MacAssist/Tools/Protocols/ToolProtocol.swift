
import Foundation

protocol ToolProtocol: Identifiable, ObservableObject {
    var name: String { get }
    var description: String { get } // Used for the AI to understand the tool's purpose
    func execute(arguments: [String: Any]) async throws -> String
}
