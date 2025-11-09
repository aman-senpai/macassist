import Foundation
import Speech
import AVFoundation
import Combine // Explicitly import Combine for clarity, although Foundation often re-exports it.

/// Represents the current state of the conversation manager.
enum ConversationState: Equatable {
    case idle           // Ready to start or waiting for user interaction
    case listening      // Actively listening for user speech
    case processing     // User speech has been transcribed, sending to AI
    case speaking       // AI response is being spoken
    case error(ConversationError) // An error occurred
}

/// Custom errors specific to the ConversationManager.
enum ConversationError: Error, LocalizedError, Equatable {
    case speechRecognitionPermissionDenied
    case speechRecognitionRestricted
    case speechRecognitionNotDetermined
    case microphonePermissionDenied
    case speechRecognizerUnavailable
    case audioEngineFailed(Error) // New: For errors related to starting the audio engine
    case noSpeechDetected
    case openAIError(AIServiceError) // New: For errors from the OpenAI service
    case conversationManagerNotReady // New: For cases where OpenAI service isn't initialized
    case unknownError(Error) // ADDED: For generic, unhandled errors

    var errorDescription: String? {
        switch self {
        case .speechRecognitionPermissionDenied:
            return "Speech recognition permission denied. Please enable it in System Settings > Privacy & Security > Microphone and Speech Recognition for MacAssist."
        case .speechRecognitionRestricted:
            return "Speech recognition is restricted on this device."
        case .speechRecognitionNotDetermined:
            return "Speech recognition permission has not been determined."
        case .microphonePermissionDenied:
            return "Microphone permission denied. Please enable it in System Settings > Privacy & Security > Microphone for MacAssist."
        case .speechRecognizerUnavailable:
            return "Speech recognizer is not available for the current locale."
        case .audioEngineFailed(let error):
            return "Audio engine failed to start: \(error.localizedDescription)"
        case .noSpeechDetected:
            return "No speech detected. Tap 'Start' to try again."
        case .openAIError(let error):
            return error.localizedDescription
        case .conversationManagerNotReady:
            return "Conversation manager is not ready. OpenAI service failed to initialize."
        case .unknownError(let error): // ADDED: Error description for unknown errors
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    // Custom Equatable implementation for associated values
    static func == (lhs: ConversationError, rhs: ConversationError) -> Bool {
        switch (lhs, rhs) {
        case (.speechRecognitionPermissionDenied, .speechRecognitionPermissionDenied),
             (.speechRecognitionRestricted, .speechRecognitionRestricted),
             (.speechRecognitionNotDetermined, .speechRecognitionNotDetermined),
             (.microphonePermissionDenied, .microphonePermissionDenied),
             (.speechRecognizerUnavailable, .speechRecognizerUnavailable),
             (.noSpeechDetected, .noSpeechDetected),
             (.conversationManagerNotReady, .conversationManagerNotReady):
            return true
        case (.audioEngineFailed(let e1), .audioEngineFailed(let e2)):
            // This is a simplified comparison; for robust error comparison, you might compare error codes/domains
            return e1.localizedDescription == e2.localizedDescription
        case (.openAIError(let e1), .openAIError(let e2)):
            // Compare OpenAI specific errors
            return e1.localizedDescription == e2.localizedDescription
        case (.unknownError(let e1), .unknownError(let e2)): // ADDED: Equatable for unknown errors
            return e1.localizedDescription == e2.localizedDescription
        default:
            return false
        }
    }
}


/// Manages the full voice-based, back-and-forth conversation flow.
class ConversationManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate, SFSpeechRecognitionTaskDelegate {

    // MARK: - Published Properties for UI Updates

    @Published var state: ConversationState = .idle
    @Published var userTranscript: String = "" // What the user has said
    @Published var aiResponse: String = ""    // What the AI has responded

    // MARK: - Speech Recognition Properties

    // The speech recognizer for the specified locale.
    private let speechRecognizer: SFSpeechRecognizer?
    // The recognition request that provides audio to the speech recognizer.
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    // The recognition task that manages the lifetime of a speech recognition session.
    private var recognitionTask: SFSpeechRecognitionTask?
    // An audio engine to manage the audio input.
    private let audioEngine = AVAudioEngine()
    // Timer to detect periods of silence and automatically end speech input.
    private var silenceTimer: Timer?
    
    // Hold a strong reference to the inputNode so we can remove tap reliably
    private var inputNode: AVAudioInputNode {
        audioEngine.inputNode
    }


    // MARK: - Text-to-Speech Properties

    // The speech synthesizer to convert text to spoken audio.
    private let speechSynthesizer = AVSpeechSynthesizer()


    // MARK: - AI Integration Properties
    private var openAIService: AIService?
    private var conversationMessages: [AIService.ChatMessage] = [] // CHANGED: Qualified ChatMessage

    // The system prompt to initialize the AI conversation, matching your Python script.
    private let systemPrompt = """
    You're an expert voice agent. You are given the transcript of what the user has said using voice.
    You need to output as if you are a voice agent, and whatever you speak will be converted back to audio
    using AI and played back to the user. Keep your responses concise and conversational.
    """


    private let historyManager: HistoryManager

    // MARK: - Initialization

    init(historyManager: HistoryManager) {
        self.historyManager = historyManager
        // Initialize speech recognizer for English (US). You can change the locale.
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        speechRecognizer?.delegate = self
        speechSynthesizer.delegate = self
        
        // Initialize OpenAI Service
        do {
            self.openAIService = try AIService()
        } catch {
            print("Failed to initialize OpenAI Service: \(error.localizedDescription)")
            self.state = .error(error as? ConversationError ?? .conversationManagerNotReady)
        }

        // Request necessary permissions when the manager is initialized.
        requestPermissions()
        setupInitialConversationMessages()
    }

    private func setupInitialConversationMessages() {
        // CHANGED: Qualified ChatMessage and ChatRole
        conversationMessages = [AIService.ChatMessage(role: .system, content: systemPrompt)]
    }

    // MARK: - Permission Handling

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            OperationQueue.main.addOperation { // Ensure UI updates on main thread
                switch authStatus {
                case .authorized:
                    // On macOS, AVCaptureDevice is used to request microphone access
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async { // Ensure UI updates on main thread
                            if !granted {
                                self.state = .error(ConversationError.microphonePermissionDenied)
                            } else {
                                // If both speech and microphone permissions are granted, go to idle
                                // Ensure OpenAI service is ready before going to idle
                                if self.openAIService != nil {
                                    self.state = .idle
                                } else {
                                    self.state = .error(.conversationManagerNotReady)
                                }
                            }
                        }
                    }
                case .denied:
                    self.state = .error(ConversationError.speechRecognitionPermissionDenied)
                case .restricted:
                    self.state = .error(ConversationError.speechRecognitionRestricted)
                case .notDetermined:
                    self.state = .error(ConversationError.speechRecognitionNotDetermined)
                @unknown default:
                    fatalError("Unknown authorization status for SFSpeechRecognizer")
                }
            }
        }
    }
    
    // MARK: - Internal Cleanup
    
    /// Cleans up resources related to speech recognition.
    private func cleanupRecognitionResources() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel() // Ensure the task is cancelled
        recognitionTask = nil
        recognitionRequest?.endAudio() // End audio for the request
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            // It's safer to remove tap when not running, or right before stop()
            inputNode.removeTap(onBus: 0)
        }
    }


    // MARK: - Speech Recognition (User Input)

    /// Starts the audio engine and speech recognition process.
    func startListening() throws {
        // Ensure previous task is cancelled and resources are cleaned up.
        cleanupRecognitionResources()

        // Guard against starting if recognizer is unavailable or permissions are not set.
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw ConversationError.speechRecognizerUnavailable
        }
        
        // Ensure state is appropriate to start listening
        // Allow starting from idle, noSpeechDetected error, or speechRecognizerUnavailable error.
        guard state == .idle || state == .error(.noSpeechDetected) || state == .error(.speechRecognizerUnavailable) else {
            print("Cannot start listening in current state: \(state)")
            return
        }

        // Stop the engine and remove tap before re-configuring if it's somehow still running
        if audioEngine.isRunning {
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
        }

        // Create a new recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object.")
        }
        recognitionRequest.shouldReportPartialResults = true

        // Create a recognition task using the delegate method.
        // The delegate methods will now handle results, errors, and task lifecycle.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest, delegate: self)

        // Install an audio tap on the input node to provide audio buffers to the recognition request.
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare() // Prepare the audio engine for startup.
        do {
            try audioEngine.start() // Start the audio engine.
            // Start the silence timer immediately after the audio engine starts.
            // This ensures that if no speech is detected from the beginning, the recognition
            // task will still end after the specified silence duration.
            DispatchQueue.main.async {
                self.startSilenceTimer()
            }
        } catch {
            // Use the new error case for audio engine failures.
            self.cleanupRecognitionResources() // Ensure cleanup on error
            throw ConversationError.audioEngineFailed(error)
        }

        // Update the state and clear previous data.
        state = .listening
        userTranscript = ""
        aiResponse = ""
        print("Started listening...")
    }

    /// Helper to start or reset the silence detection timer.
    private func startSilenceTimer() {
        silenceTimer?.invalidate() // Invalidate any existing timer
        // Set a timeout, e.g., 3.0 seconds of silence, before ending the audio session.
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("Silence detected, automatically ending audio for recognition request.")
            // Calling endAudio() will cause the recognition task to finalize and
            // trigger its `didFinishRecognition` or `didFailWithError` delegate methods.
            self.recognitionRequest?.endAudio()
            // The timer will be invalidated again by cleanupRecognitionResources, but explicit here for clarity.
            self.silenceTimer?.invalidate()
            self.silenceTimer = nil
        }
    }

    /// Stops the audio engine and speech recognition.
    /// This is typically called for a full conversation reset, not for ending a single user turn.
    func stopListening() {
        cleanupRecognitionResources()
        print("Stopped listening.")
    }

    // MARK: - AI Integration (Processing User Input)

    /// Processes the user's final transcript and retrieves an AI response.
    private func processTranscript(_ text: String) {
        state = .processing
        print("Processing transcript: \(text)")

        // --- REPLACE THIS WITH YOUR ACTUAL AI INTEGRATION ---
        // Ensure OpenAI service is available
        guard let openAIService = openAIService else {
            DispatchQueue.main.async {
                self.state = .error(.conversationManagerNotReady)
            }
            return
        }

        // Add user's message to the conversation history
        // CHANGED: Qualified ChatMessage and ChatRole
        conversationMessages.append(AIService.ChatMessage(role: .user, content: text))

        Task {
            do {
                let aiResponseContent = try await openAIService.getChatCompletion(messages: self.conversationMessages)
                DispatchQueue.main.async {
                    self.aiResponse = aiResponseContent
                    // Add AI's response to the conversation history
                    // CHANGED: Qualified ChatMessage and ChatRole
                    self.conversationMessages.append(AIService.ChatMessage(role: .assistant, content: aiResponseContent))
                    self.speakResponse(aiResponseContent)
                }
            } catch let serviceError as AIServiceError {
                DispatchQueue.main.async {
                    print("OpenAI Service Error: \(serviceError.localizedDescription)")
                    self.state = .error(.openAIError(serviceError))
                    self.userTranscript = "" // Clear transcript on error.
                }
            } catch {
                DispatchQueue.main.async {
                    print("Unknown error getting AI response: \(error.localizedDescription)")
                    self.state = .error(.unknownError(error)) // CHANGED: Use the new unknownError case
                    self.userTranscript = "" // Clear transcript on error.
                }
            }
        }
        // --- END OF AI INTEGRATION SECTION ---
    }

    /// Placeholder for your actual AI service integration.
    /// You would replace this function with calls to an LLM API (e.g., OpenAI, Gemini, local model).
    // This mock function is now replaced by the OpenAIService integration
    /*
    private func mockAIResponse(for text: String) async -> String {
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Simulate network delay (1 second)

        // Simple keyword-based responses for demonstration
        if text.lowercased().contains("hello") {
            return "Hello there! How can I assist you today?"
        } else if text.lowercased().contains("how are you") {
            return "I'm just a computer program, but I'm functioning well. Thanks for asking!"
        } else if text.lowercased().contains("what is your name") {
            return "I don't have a name. I am an AI assistant."
        } else if text.lowercased().contains("tell me a joke") {
            return "Why don't scientists trust atoms? Because they make up everything!"
        } else if text.lowercased().contains("quit") || text.lowercased().contains("goodbye") {
            return "Goodbye! It was nice chatting with you."
        } else if text.lowercased().contains("swiftui") {
             return "SwiftUI is Apple's declarative UI framework, making it easier to build apps across all Apple platforms."
        }
        return "I heard you say: \"\(text)\". What would you like to talk about next?"
    }
    */

    // MARK: - Text-to-Speech (AI Output)

    /// Converts the AI's text response into spoken audio.
    private func speakResponse(_ text: String) {
        state = .speaking
        print("Speaking response: \(text)")
        let utterance = AVSpeechUtterance(string: text)
        // You can customize the voice (e.g., "en-US", "en-GB", specific voice identifiers).
        // To match the Python script's 'Isha' voice, you'd need to find its equivalent
        // among AVSpeechSynthesisVoice.speechVoices(). For now, we keep "en-US".
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
        utterance.rate = 0.52 // Adjust speech rate (0.0 to 1.0), 0.52 is roughly 200 words/min
        utterance.pitchMultiplier = 1.0 // Adjust pitch (0.5 to 2.0)
        utterance.volume = 1.0 // Adjust volume (0.0 to 1.0)

        speechSynthesizer.speak(utterance)
    }

    // MARK: - SFSpeechRecognizerDelegate (Callbacks for Speech Recognition)

    /// Called when the speech recognizer's availability changes.
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            state = .error(ConversationError.speechRecognizerUnavailable)
            print("Speech recognizer is no longer available.")
        } else if case .error(let error) = state, error == .speechRecognizerUnavailable {
            // If it was unavailable and now it's back, try to revert to idle if no other error is present.
            print("Speech recognizer is now available again.")
            requestPermissions() // Re-check all permissions and potentially transition to idle
        }
    }

    // MARK: - SFSpeechRecognitionTaskDelegate (Callbacks for Detailed Speech Recognition Events)

    /// Called when the recognition task is no longer detecting speech and has paused.
    func speechRecognitionTaskDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        print("Speech detected by recognition task.")
        // The silence timer is now only reset when actual transcribed content is received.
    }

    /// Called when the speech recognizer has a new (partial or final) transcription.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        // This method is called frequently as new speech is recognized (partial results).
        DispatchQueue.main.async {
            self.userTranscript = transcription.formattedString
            // Reset the silence timer every time we get new speech data.
            // This is crucial for responsive silence detection, ensuring it only resets for actual speech.
            if !self.userTranscript.isEmpty {
                self.startSilenceTimer()
            }
        }
    }

    /// Called when the recognition task has finished reading all of the audio.
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {
        print("Speech recognition task finished reading audio input.")
        // At this point, no more audio is being fed to the recognizer.
        // The `didFinishRecognition` or `didFailWithError` delegate methods will provide the final result soon.
    }

    /// Called when the recognition task has been cancelled.
    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        print("Speech recognition task was cancelled.")
        DispatchQueue.main.async {
            self.cleanupRecognitionResources() // Ensure all resources are cleaned up
            self.state = .idle // Or an appropriate error state if cancellation implies an issue
        }
    }

    /// Called when the recognition task has finished recognition and is ready to turn to other tasks.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        print("Speech recognition task did finish recognition (delegate): \(recognitionResult.bestTranscription.formattedString)")
        DispatchQueue.main.async {
            self.cleanupRecognitionResources() // Clean up resources
            if self.userTranscript.isEmpty {
                // If didFinishRecognition is called but our collected transcript is empty,
                // it implies no actual speech was recognized successfully.
                self.state = .error(.noSpeechDetected)
            } else {
                // Process the final transcript.
                self.processTranscript(self.userTranscript)
            }
        }
    }

    /// Called when the recognition task has encountered an error.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFailWithError error: Error) {
        print("Speech recognition task did fail with error (delegate): \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.cleanupRecognitionResources() // Clean up resources immediately upon error

            let nsError = error as NSError
            // Check for common "no speech detected" error from SFSpeechRecognizer (Code 203)
            if nsError.domain == "com.apple.Speech.Recognition" && nsError.code == 203 {
                if self.userTranscript.isEmpty {
                    // Truly no speech detected if transcript is empty.
                    self.state = .error(.noSpeechDetected)
                } else {
                    // Speech was detected and transcribed, but task ended with 203.
                    // This can happen if the user spoke, then stopped abruptly, or had trailing silence.
                    // We should still process the collected transcript.
                    print("Processing collected transcript despite recognition task error 203 (likely trailing silence): \(self.userTranscript)")
                    self.processTranscript(self.userTranscript)
                }
            } else {
                // For other errors, set the appropriate error state.
                self.state = .error(error as? ConversationError ?? ConversationError.speechRecognizerUnavailable)
                self.userTranscript = "" // Clear transcript on other errors.
            }
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate (Callbacks for Text-to-Speech)

    /// Called when the speech synthesizer finishes speaking an utterance.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Finished speaking AI response.")
        // After the AI finishes speaking, we automatically transition back to listening for the user.
        DispatchQueue.main.async {
            do {
                try self.startListening()
            } catch {
                print("Error restarting listening after AI speech: \(error.localizedDescription)")
                self.state = .error(error as? ConversationError ?? .audioEngineFailed(error))
            }
        }
    }

    /// Called when the speech synthesizer cancels an utterance.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("AI speech cancelled.")
        // If speech is cancelled, also try to restart listening.
        DispatchQueue.main.async {
            do {
                try self.startListening()
            } catch {
                print("Error restarting listening after AI speech cancelled: \(error.localizedDescription)")
                self.state = .error(error as? ConversationError ?? .audioEngineFailed(error))
            }
        }
    }

    // REMOVED: Duplicate declaration of historyManager
    // private let historyManager = HistoryManager()

    // MARK: - Lifecycle / Reset

    /// Resets the conversation manager to its initial idle state, stopping all active processes.
    func reset() {
        stopListening() // This will clear all recognition-related resources.
        speechSynthesizer.stopSpeaking(at: .immediate) // Stop any ongoing AI speech
        
        // Save the conversation to history before clearing it
        let filteredMessages = conversationMessages.filter { $0.role != .system }
        if !filteredMessages.isEmpty {
            let messages = filteredMessages.map { Message(id: UUID(), content: $0.content ?? "", role: $0.role.rawValue, timestamp: Date()) }
            let conversation = Conversation(id: UUID(), messages: messages, timestamp: Date())
            historyManager.saveConversation(conversation)
        }
        
        state = .idle
        userTranscript = ""
        aiResponse = ""
        setupInitialConversationMessages() // Re-initialize conversation history
        print("Conversation Manager reset.")
    }
}
