import Foundation
import Combine

struct Message: Codable, Identifiable, Hashable {
    let id: UUID
    let content: String
    let role: String
    let timestamp: Date
}

struct Conversation: Codable, Identifiable, Hashable, Equatable {
    let id: UUID
    var messages: [Message]
    var timestamp: Date
    
    var title: String {
        // Find the first user message to use as a title
        if let firstUserMessage = messages.first(where: { $0.role == "user" }) {
            // Return the first 30 characters of the content
            return String(firstUserMessage.content.prefix(30))
        }
        return "New Conversation"
    }
    
    // Conform to Equatable
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
    
    // Conform to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class HistoryManager: ObservableObject {
    @Published var conversationHistory: [Conversation] = []
    
    // URL for the current session's JSON file
    private let currentSessionFileURL: URL
    
    // Directory where all session files are stored
    private let sessionsDirectory: URL

    init() {
        // 1. Initialize 'sessionsDirectory' first.
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.sessionsDirectory = documentsDirectory.appendingPathComponent("ConversationSessions")
        
        // Now 'sessionsDirectory' is initialized. We can use a static helper for directory creation.
        HistoryManager.createSessionsDirectoryIfNeeded(at: self.sessionsDirectory)
        
        // Declare local variables to store the computed values for properties
        let initialConversationHistory: [Conversation]
        let initialCurrentSessionFileURL: URL
        
        // 2. Perform logic to determine 'initialConversationHistory' and 'initialCurrentSessionFileURL'
        // using static helper methods or direct computations that don't rely on 'self'.
        let allSessionFiles = HistoryManager.listAllSessionFiles(in: self.sessionsDirectory).sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
        
        if let mostRecentFile = allSessionFiles.first {
            if let loadedConversations = HistoryManager.loadSessionHistory(from: mostRecentFile) {
                initialConversationHistory = loadedConversations
                initialCurrentSessionFileURL = mostRecentFile
                print("Loaded history from existing session: \(mostRecentFile.lastPathComponent)")
            } else {
                // If loading the most recent file failed, create a new session
                initialCurrentSessionFileURL = HistoryManager.generateNewSessionFileURL(in: self.sessionsDirectory)
                initialConversationHistory = [] // No history loaded
                print("Failed to load most recent session. Starting new session. History will be saved to: \(initialCurrentSessionFileURL.lastPathComponent)")
            }
        } else {
            // No previous sessions found, start a new one
            initialCurrentSessionFileURL = HistoryManager.generateNewSessionFileURL(in: self.sessionsDirectory)
            initialConversationHistory = [] // No history loaded
            print("No previous sessions found. Starting new session. History will be saved to: \(initialCurrentSessionFileURL.lastPathComponent)")
        }
        
        // 3. Finally, assign the computed values to the stored properties.
        // At this point, ALL stored properties (including currentSessionFileURL and conversationHistory)
        // are definitively initialized. 'self' can now be used freely.
        self.currentSessionFileURL = initialCurrentSessionFileURL
        self.conversationHistory = initialConversationHistory
    }

    /// Helper to generate a unique filename for a new session using a timestamp. Made static.
    private static func generateNewSessionFileURL(in directory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "session_\(timestamp).json"
        return directory.appendingPathComponent(filename)
    }

    /// Creates the 'ConversationSessions' directory if it doesn't already exist. Made static.
    private static func createSessionsDirectoryIfNeeded(at directory: URL) {
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                print("Created sessions directory: \(directory.lastPathComponent)")
            } catch {
                print("Error creating sessions directory at \(directory.lastPathComponent): \(error)")
            }
        }
    }

    /// Lists all saved session JSON files in the 'ConversationSessions' directory. Made static.
    /// - Returns: An array of URLs pointing to the session files.
    private static func listAllSessionFiles(in directory: URL) -> [URL] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            return fileURLs.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("session_") }
        } catch {
            print("Error listing session files from \(directory.lastPathComponent): \(error)")
            return []
        }
    }
    
    /// Loads conversation history from a specific session file. Made static.
    /// - Parameter url: The URL of the session file to load.
    /// - Returns: An optional array of `Conversation` objects if loading is successful, otherwise `nil`.
    private static func loadSessionHistory(from url: URL) -> [Conversation]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Session file not found at path: \(url.lastPathComponent)")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601 // Consistent date decoding
            let loadedConversations = try decoder.decode([Conversation].self, from: data)
            print("Successfully loaded session history from: \(url.lastPathComponent)")
            return loadedConversations
        } catch {
            print("Error loading session history from \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Saves or updates a conversation in the current session's history and persists it to disk.
    func saveConversation(_ conversation: Conversation) {
        // If the conversation already exists (based on ID), update it. Otherwise, append it.
        if let index = conversationHistory.firstIndex(where: { $0.id == conversation.id }) {
            conversationHistory[index] = conversation
        } else {
            conversationHistory.append(conversation)
        }
        saveCurrentSessionHistory() // Persist changes to the current session file
    }

    /// Saves the current session's conversation history to its dedicated JSON file.
    func saveCurrentSessionHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // Makes the JSON file human-readable
            encoder.dateEncodingStrategy = .iso8601 // Consistent date formatting
            
            let data = try encoder.encode(conversationHistory)
            try data.write(to: currentSessionFileURL)
            print("Successfully saved current session history to: \(currentSessionFileURL.lastPathComponent)")
        } catch {
            print("Error saving current session history to \(currentSessionFileURL.lastPathComponent): \(error)")
        }
    }
    
    func deleteConversation(_ conversation: Conversation) {
        if let index = conversationHistory.firstIndex(where: { $0.id == conversation.id }) {
            conversationHistory.remove(at: index)
            // After removing the conversation from the array, save the updated array back to the session file.
            saveCurrentSessionHistory()
            print("Deleted conversation with ID: \(conversation.id) from history and resaved current session.")
        }
        // No need to try and delete a separate file for the conversation, as all conversations
        // are stored within the single currentSessionFileURL.
    }

    func deleteAllHistory() {
        conversationHistory.removeAll()
        let allSessionFiles = HistoryManager.listAllSessionFiles(in: sessionsDirectory)
        for fileURL in allSessionFiles {
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("Deleted session file: \(fileURL.lastPathComponent)")
            } catch {
                print("Error deleting session file \(fileURL.lastPathComponent): \(error)")
            }
        }
        // After deleting all session files, ensure the current one is also cleared if it exists.
        // It's already handled by removeAll() and the loop will iterate over it.
        // If there are no session files, a new empty one will be created on next app launch/init.
    }
}

