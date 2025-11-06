import Foundation
import AVFoundation
import Speech
import Combine

class SpeechAndAudioService: NSObject, ObservableObject, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {

    // MARK: - Published Properties
    @Published var liveTranscript: String = "" // For displaying partial results in UI
    @Published var isRecording: Bool = false
    @Published var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var speechErrorMessage: String? // Optional error message for UI alerts
    
    // MARK: - Internal State
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var silenceTimer: Timer?
    
    // Callbacks for ContentView to react to
    var onFinalTranscript: ((String) -> Void)?
    
    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        self.speechRecognizer?.delegate = self
        self.speechSynthesizer.delegate = self
        
        requestSpeechAuthorization() // Request permissions on initialization
    }
    
    deinit {
        stopRecording()
        speechSynthesizer.stopSpeaking(at: .immediate)
        silenceTimer?.invalidate()
        print("SpeechAndAudioService deinitialized.")
    }
    
    // MARK: - Authorization
    
    func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async { // Ensure UI updates on main thread
                self.speechAuthorizationStatus = authStatus
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized.")
                    // Also check microphone authorization as it's separate on macOS
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            if !granted {
                                self.speechErrorMessage = "Microphone access denied. Please enable it in System Settings > Privacy & Security > Microphone for MacAssist."
                            } else {
                                self.speechErrorMessage = nil // Clear any previous error
                            }
                        }
                    }
                case .denied:
                    self.speechErrorMessage = "Speech recognition access denied. Please enable it in System Settings > Privacy & Security > Microphone and Speech Recognition for MacAssist."
                    print("User denied speech recognition access.")
                case .restricted:
                    self.speechErrorMessage = "Speech recognition restricted on this device. This may be due to parental controls or other system settings."
                    print("Speech recognition restricted on this device.")
                case .notDetermined:
                    print("Speech recognition not yet authorized. The request dialog should have appeared.")
                @unknown default:
                    self.speechErrorMessage = "An unknown speech recognition authorization status occurred."
                    print("Unknown speech recognition authorization status.")
                }
            }
        }
    }
    
    // MARK: - Speech Recognition
    
    func startRecording() {
        guard !isRecording else {
            print("Already recording.")
            return
        }

        // Pre-flight checks
        guard speechAuthorizationStatus == .authorized else {
            self.speechErrorMessage = "Speech recognition is not authorized. Please grant microphone and speech recognition access in System Settings."
            return
        }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            self.speechErrorMessage = "Speech recognizer is not available on this device or for this language."
            return
        }
        
        cleanupRecognitionResources() // Ensure a clean slate before starting

        do {
            let newAudioEngine = AVAudioEngine()
            self.audioEngine = newAudioEngine
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                self.speechErrorMessage = "Failed to create a speech recognition request."
                cleanupRecognitionResources()
                return
            }
            recognitionRequest.shouldReportPartialResults = true
            
            let inputNode = newAudioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, when) in
                self?.recognitionRequest?.append(buffer)
            }
            
            newAudioEngine.prepare()
            try newAudioEngine.start()
            
            self.startSilenceTimer()
            
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                var isFinal = false
                
                if let result = result {
                    self.liveTranscript = result.bestTranscription.formattedString
                    isFinal = result.isFinal
                    
                    // Reset the silence timer if new speech is recognized (even partial)
                    if !self.liveTranscript.isEmpty {
                        self.startSilenceTimer()
                    }
                }
                
                if error != nil || isFinal {
                    // This block runs when the task completes, whether by error, silence, or explicit endAudio()
                    let finalTranscript = self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

                    self.cleanupRecognitionResources() // Clean up resources
                    self.isRecording = false // Stop recording state
                    self.liveTranscript = "" // Clear live transcript after task completion
                    
                    if isFinal && !finalTranscript.isEmpty {
                        self.onFinalTranscript?(finalTranscript)
                    } else if let error = error {
                        print("Speech Recognition Task Error: \(error.localizedDescription)")
                        let nsError = error as NSError
                        // Error code 203 usually means "no speech detected" or "silent"
                        if !(nsError.domain == "com.apple.Speech.Recognition" && nsError.code == 203) {
                            self.speechErrorMessage = "Speech recognition error: \(error.localizedDescription)"
                        } else {
                            // If it's a 203 error but we have a non-empty transcript, treat it as a final result.
                            // This can happen if user spoke, then paused, then task finished due to silence.
                            if !finalTranscript.isEmpty {
                                self.onFinalTranscript?(finalTranscript)
                            } else {
                                print("No speech detected.")
                                // self.speechErrorMessage = "No speech detected." // Optionally alert user
                            }
                        }
                    }
                }
            }
            
            isRecording = true
            liveTranscript = "" // Clear previous transcript
            speechErrorMessage = nil // Clear any previous error on successful start
            print("Speech recording started.")
        } catch {
            self.speechErrorMessage = "Error starting audio engine: \(error.localizedDescription)"
            print("Error starting recording: \(error.localizedDescription)")
            cleanupRecognitionResources()
            isRecording = false
        }
    }
    
    func stopRecording() {
        guard isRecording else { return } // Only stop if recording is active
        
        let currentFinalTranscript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        
        cleanupRecognitionResources()
        isRecording = false
        liveTranscript = "" // Clear live transcript
        
        // If user explicitly stops and there's a partial transcript, treat it as final
        if !currentFinalTranscript.isEmpty {
            onFinalTranscript?(currentFinalTranscript)
        }
        print("Speech recording stopped.")
    }
    
    private func cleanupRecognitionResources() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        audioEngine?.stop()
        // It's important to remove the tap from the input node to prevent memory leaks.
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        print("Speech recognition resources cleaned up.")
    }
    
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        // Set a timeout, e.g., 2.0 seconds of silence, before ending the audio session.
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("Silence detected by timer, ending audio for recognition request.")
            // This will trigger the recognitionTask's completion block with isFinal = true (or error)
            self.recognitionRequest?.endAudio()
            self.silenceTimer?.invalidate() // Invalidate immediately
            self.silenceTimer = nil
        }
    }
    
    // MARK: - Speech Synthesis
    
    func speak(text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate) // Stop any current speech
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") // You can customize language/voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate // Or adjust as needed
        
        speechSynthesizer.speak(utterance)
        print("Speaking: '\(text)'")
    }
    
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            print("Speech synthesis stopped.")
        }
    }
    
    // MARK: - SFSpeechRecognizerDelegate
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available {
                self.speechErrorMessage = "Speech recognition is currently unavailable for this device or language."
                print("Speech recognizer availability changed: Not available.")
            } else if self.speechAuthorizationStatus == .authorized {
                self.speechErrorMessage = nil // Clear error if it was related to availability
                print("Speech recognizer availability changed: Available.")
            }
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // Optional: Implement if UI needs to react when speech starts
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Optional: Implement if UI needs to react when speech finishes
        print("Finished speaking.")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Optional: Implement if UI needs to react when speech is cancelled
        print("Speech cancelled.")
    }
}
