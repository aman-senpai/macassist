
import Foundation

protocol ToolProtocol: Identifiable, ObservableObject {
    var name: String { get }
    var description: String { get }
    func execute(arguments: [String: Any]) async throws -> String
}
