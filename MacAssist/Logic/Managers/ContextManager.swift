import Foundation
import Combine
import SwiftUI

struct ContextItem: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var text: String
    var isEnabled: Bool
    
    init(id: UUID = UUID(), title: String = "New Context", text: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.text = text
        self.isEnabled = isEnabled
    }
    
    // Custom decoding to handle legacy data without 'title'
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        // Default title if missing
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "New Context"
    }
}

class ContextManager: ObservableObject {
    @Published var contexts: [ContextItem] = []
    
    private let contextsFileURL: URL
    
    init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.contextsFileURL = documentsDirectory.appendingPathComponent("Contexts.json")
        
        loadContexts()
    }
    
    func addContext(text: String) {
        let newContext = ContextItem(text: text)
        contexts.append(newContext)
        saveContexts()
    }
    
    func updateContext(_ context: ContextItem) {
        if let index = contexts.firstIndex(where: { $0.id == context.id }) {
            contexts[index] = context
            saveContexts()
        }
    }
    
    func deleteContext(_ context: ContextItem) {
        if let index = contexts.firstIndex(where: { $0.id == context.id }) {
            contexts.remove(at: index)
            saveContexts()
        }
    }
    
    func deleteContext(at offsets: IndexSet) {
        contexts.remove(atOffsets: offsets)
        saveContexts()
    }
    
    private func saveContexts() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(contexts)
            try data.write(to: contextsFileURL)
        } catch {
            print("Error saving contexts: \(error)")
        }
    }
    
    private func loadContexts() {
        guard FileManager.default.fileExists(atPath: contextsFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: contextsFileURL)
            let decoder = JSONDecoder()
            contexts = try decoder.decode([ContextItem].self, from: data)
        } catch {
            print("Error loading contexts: \(error)")
        }
    }
}
