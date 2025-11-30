//
//  SettingsView.swift
//  MacAssist
//
//  Created by Aman Raj on 01/12/25.
//

import SwiftUI
import AVFoundation

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case provider = "Provider"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .general: return "gear"
        case .provider: return "brain"
        }
    }
}

struct SettingsView: View {
    @State private var selectedCategory: SettingsCategory? = .provider
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                NavigationLink(value: category) {
                    Label(category.rawValue, systemImage: category.icon)
                }
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
        } detail: {
            if let category = selectedCategory {
                switch category {
                case .general:
                    GeneralSettingsView()
                case .provider:
                    ProviderSettingsView()
                }
            } else {
                Text("Select a category")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("speechVoiceIdentifier") private var speechVoiceIdentifier: String = "com.apple.ttsbundle.siri_female_en-US_compact"
    @AppStorage("speechRate") private var speechRate: Double = 0.5
    @AppStorage("silenceTimeout") private var silenceTimeout: Double = 2.0
    @AppStorage("openAIApiKey") private var openAIApiKey: String = ""
    
    // Get available voices
    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "en") }
    }
    
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appTheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            
            Section("Speech") {
                Picker("Voice", selection: $speechVoiceIdentifier) {
                    ForEach(availableVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }
                .onAppear {
                    // Ensure a valid voice is selected
                    if !availableVoices.contains(where: { $0.identifier == speechVoiceIdentifier }) {
                        if let firstVoice = availableVoices.first {
                            speechVoiceIdentifier = firstVoice.identifier
                        }
                    }
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Speech Rate")
                        Spacer()
                        Text(String(format: "%.2f", speechRate))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $speechRate, in: 0.0...1.0) {
                        Text("Speech Rate")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").font(.caption)
                    } maximumValueLabel: {
                        Image(systemName: "hare").font(.caption)
                    }
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Silence Timeout")
                        Spacer()
                        Text(String(format: "%.1fs", silenceTimeout))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $silenceTimeout, in: 0.5...5.0, step: 0.5) {
                        Text("Silence Timeout")
                    } minimumValueLabel: {
                        Text("0.5s").font(.caption)
                    } maximumValueLabel: {
                        Text("5.0s").font(.caption)
                    }
                }
            }
            
            // Legacy Notice (if old API key exists)
            if !openAIApiKey.isEmpty && !UserDefaults.standard.bool(forKey: "llm_settings_migrated") {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Settings Migration")
                                .font(.headline)
                                .bold()
                        }
                        Text("Your OpenAI API key has been migrated to the new provider settings. You can now choose between OpenAI, Gemini, and Ollama.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
