//
//  VoiceAssistantController.swift
//  MacAssist
//
//  Created by Aman Raj on 5/11/25.
//

import Foundation
import SwiftUI
import Combine
import Speech
import AVFoundation

@MainActor
final class VoiceAssistantController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // MARK: - Published Properties for UI
    @Published var agent = AetherAgent()
    @Published var currentInput: String = ""
    @Published var isRecording: Bool = false
    @Published var isContinuousConversationActive: Bool = false
    @Published var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    // Error state for alerts
    @Published var showingSpeechErrorAlert: Bool = false
    @Published var speechErrorMessage: String = ""
    
    // MARK: - Private Properties
    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    // Use a single, persistent audio engine instance.
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        
        // Observe agent's spoken response to trigger text-to-speech
        agent.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let self = self, let lastMessage = messages.last, lastMessage.role == "assistant" else {
                    return
                }
                
                if self.isContinuousConversationActive {
                    self.speak(text: lastMessage.content ?? "")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func toggleContinuousConversation() {
        isContinuousConversationActive.toggle()
        if isContinuousConversationActive {
            currentInput = ""
            startRecording()
        } else {
            stopRecording()
        }
    }
    
    func sendMessage() {
        let text = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !agent.isProcessing else { return }
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .word)
        }
        
        currentInput = ""
        agent.sendMessage(text: text)
    }
    
    // MARK: - Speech Synthesis (Text-to-Speech)
    private func speak(text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        speechSynthesizer.speak(utterance)
    }
    
    // AVSpeechSynthesizerDelegate callback
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // After AI finishes speaking, if we're in continuous mode, restart listening.
        Task {
            await MainActor.run {
                if self.isContinuousConversationActive {
                    print("AI speech finished. Restarting listening.")
                    self.startRecording()
                }
            }
        }
    }
    
    // MARK: - Speech Recognition
    
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task {
                await MainActor.run {
                    print("Silence detected, ending audio recognition request.")
                    self?.recognitionRequest?.endAudio()
                    self?.silenceTimer?.invalidate()
                    self?.silenceTimer = nil
                }
            }
        }
    }
    
    func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task {
                await MainActor.run {
                    self?.speechAuthorizationStatus = authStatus
                    if authStatus != .authorized {
                        self?.speechErrorMessage = "Speech recognition access is required. Please enable it in System Settings > Privacy & Security."
                        self?.showingSpeechErrorAlert = true
                    }
                }
            }
        }
    }
    
        private func startRecording() {
            // Barge-in: If the AI is speaking, interrupt it.
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
            
            guard speechAuthorizationStatus == .authorized, let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
                speechErrorMessage = "Speech recognition is not authorized or available."
                showingSpeechErrorAlert = true
                isContinuousConversationActive = false
                return
            }
            
            // Ensure any previous session is completely torn down before starting a new one.
            stopAudioEngine()
            
            do {
                recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                guard let recognitionRequest = recognitionRequest else { throw URLError(.cannotCreateFile) }
                recognitionRequest.shouldReportPartialResults = true
                
                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    self.recognitionRequest?.append(buffer)
                }
                
                audioEngine.prepare()
                try audioEngine.start()
                startSilenceTimer()
                
                isRecording = true
                
                            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                                Task {
                                    await MainActor.run {
                                        guard let self = self else { return }
                                        var isFinal = false
                                        
                                        if let result = result {
                                            self.currentInput = result.bestTranscription.formattedString
                                            isFinal = result.isFinal
                                            if !self.currentInput.isEmpty {
                                                self.startSilenceTimer()
                                            }
                                        }
                                        
                                        if error != nil || isFinal {
                                            self.stopAudioEngine()
                                            let trimmedInput = self.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                
                                            // Success Case: A final, non-empty transcript was received.
                                            if isFinal, !trimmedInput.isEmpty {
                                                self.sendMessage()
                                                // Don't return; allow cleanup logic below to run
                                            }
                                            
                                            // Error & Empty Result Handling:
                                            if let error = error {
                                                print("Speech recognition failed, handling silently: \(error.localizedDescription)")
                                            }
                                            
                                            // For any non-success case (error or empty final transcript),
                                            // pause the continuous conversation mode if it's active.
                                            if self.isContinuousConversationActive && (error != nil || trimmedInput.isEmpty) {
                                                print("Pausing continuous conversation due to empty or failed recognition.")
                                                self.isContinuousConversationActive = false
                                            }
                                            
                                            self.currentInput = "" // Always clear the input after processing is finished.
                                        }
                                    }
                                }
                            }            } catch {
                print("Error starting audio engine, handling silently: \(error.localizedDescription)")
                stopAudioEngine()
                isContinuousConversationActive = false
            }
        }
    
        private func stopRecording() {
            // This is for explicit user stops. Finalize the recognition to process any buffered speech.
            if audioEngine.isRunning {
                recognitionRequest?.endAudio()
                recognitionTask?.finish()
            }
            // Ensure cleanup even if the engine wasn't running.
            stopAudioEngine()
        }
    
        private func stopAudioEngine() {
            // This is now the single, robust cleanup function. It is safe to call multiple times.
            if audioEngine.isRunning {
                audioEngine.stop()
                // A tap is only guaranteed to exist if the engine was running.
                // Removing it conditionally prevents crashes.
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            
            recognitionRequest = nil
            recognitionTask?.cancel() // Cancel to prevent any lingering completion handlers.
            recognitionTask = nil
            
            isRecording = false
            silenceTimer?.invalidate()
            silenceTimer = nil
        }
    }
