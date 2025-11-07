//
// SystemTools.swift
// MacAssist
//
// Created by Aman Raj on 5/11/25.
//

import Foundation
import AppKit
import UniformTypeIdentifiers


enum ToolExecutionError: Error, LocalizedError {
  case missingArgument(String)
  case invalidArgument(String)
  case fileOperationFailed(String)
  case shellCommandFailed(String, Int, String)
  case unexpectedError(String)
  case summarizationFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingArgument(let arg): return "Missing required argument: \(arg)."
    case .invalidArgument(let arg): return "Invalid argument value: \(arg)."
    case .fileOperationFailed(let message): return "File operation failed: \(message)"
    case .shellCommandFailed(let command, let exitCode, let output):
      return "Command '\(command)' failed with exit code \(exitCode). Output: \(output.isEmpty ? "No error output." : output)"
    case .unexpectedError(let message): return "An unexpected error occurred: \(message)"
    case .summarizationFailed(let message): return "Summarization failed: \(message)"
    }
  }
}


final class SystemTools {

  private func executeAppleScript(_ script: String) async -> Result<String, ToolExecutionError> {
    return await withCheckedContinuation { continuation in
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      task.arguments = ["-e", script]

      let pipe = Pipe()
      task.standardOutput = pipe
      task.standardError = pipe

      do {
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
       
        if task.terminationStatus == 0 {
          let resultString = output.isEmpty ? "Action completed successfully." : output
          continuation.resume(returning: .success(resultString))
        } else {
          continuation.resume(returning: .failure(.shellCommandFailed("osascript", Int(task.terminationStatus), output)))
        }
      } catch {
        continuation.resume(returning: .failure(.unexpectedError(error.localizedDescription)))
      }
    }
  }
 

  func openApplication(name: String) -> Result<String, ToolExecutionError> {
    let appPath = "/Applications/\(name).app"
    if FileManager.default.fileExists(atPath: appPath) {
        let success = NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
        if success {
            return .success("Successfully opened the application: \(name).")
        }
    }
    
    // If direct opening fails or app not found, try 'open -a' shell command
    let shellCommand = "open -a \"\(name)\""
    let result = runShellCommandSync(command: shellCommand)
   
    switch result {
    case .success(let output):
        return .success("Successfully launched application: \(name). Shell output: \(output)")
    case .failure:
        return .failure(.unexpectedError("Error: Could not find or open application '\(name)'. Please ensure the app name is correct and in the Applications folder."))
    }
  }

  func closeFrontmostApplication() async -> Result<String, ToolExecutionError> {
    let script = "tell application (path to frontmost application as text) to quit"
    return await executeAppleScript(script)
  }

  func minimizeFrontmostWindow() async -> Result<String, ToolExecutionError> {
    let script = "tell application \"System Events\" to tell process (name of first process whose frontmost is true) to set miniaturized of window 1 of its windows to true"
    return await executeAppleScript(script)
  }

  
  /// Simulates a "Select All" command (Command-A) in the frontmost application.
  func selectAllText() async -> Result<String, ToolExecutionError> {
    let script = "tell application \"System Events\" to keystroke \"a\" using command down"
    return await executeAppleScript(script)
  }
  
  func copySelection() async -> Result<String, ToolExecutionError> {
    let script = "tell application \"System Events\" to keystroke \"c\" using command down"
    return await executeAppleScript(script)
  }
  
  func pasteText(content: String) async -> Result<String, ToolExecutionError> {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
    
    // A small delay to ensure the pasteboard is updated before the paste command
    try? await Task.sleep(for: .milliseconds(100))
    
    let script = "tell application \"System Events\" to keystroke \"v\" using command down"
    return await executeAppleScript(script)
  }
  
  /// Types the given text at the current cursor location by simulating keystrokes.
  /// This is useful for applications that might not respond well to the standard paste command.
  /// It handles multi-line text with proper formatting, using Shift-Return for newlines.
  func typeText(content: String) async -> Result<String, ToolExecutionError> {
    // Escape characters for AppleScript string literals.
    // Backslashes and double quotes have special meaning and must be escaped.
    // Newlines (`\n`) are handled by simulating a "Shift-Return" keystroke.
    let escapedForAppleScript = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")

    let lines = escapedForAppleScript.components(separatedBy: "\n")
    
    var commands: [String] = []
    for (index, line) in lines.enumerated() {
        if !line.isEmpty {
            commands.append("keystroke \"\(line)\"")
        }
        
        if index < lines.count - 1 {
            commands.append("keystroke return using {shift down}")
        }
    }
    
    let script = """
    tell application "System Events"
        \(commands.joined(separator: "\n        "))
    end tell
    """
    
    return await executeAppleScript(script)
  }
  
  func replaceAllText(with newContent: String) async -> Result<String, ToolExecutionError> {
    let pasteboard = NSPasteboard.general
    let originalContent = pasteboard.string(forType: .string)
    
    defer {
      pasteboard.clearContents()
      if let originalContent = originalContent {
        pasteboard.setString(originalContent, forType: .string)
      }
    }
    
    pasteboard.clearContents()
    pasteboard.setString(newContent, forType: .string)
    
    try? await Task.sleep(for: .milliseconds(100))
    
    let script = """
    tell application "System Events"
        keystroke "a" using command down
        delay 0.2
        keystroke "v" using command down
    end tell
    """
    return await executeAppleScript(script)
  }
  
  func getTextFromFrontmostApplication() async -> Result<String, ToolExecutionError> {
    let pasteboard = NSPasteboard.general
    let originalContent = pasteboard.string(forType: .string)
    
    defer {
      pasteboard.clearContents()
      if let originalContent = originalContent {
        pasteboard.setString(originalContent, forType: .string)
      }
    }
    
    pasteboard.clearContents()
    
    let script = """
    tell application "System Events"
        keystroke "a" using command down
        delay 0.2
        keystroke "c" using command down
    end tell
    """
    let copyResult = await executeAppleScript(script)
    
    guard case .success = copyResult else {
      return .failure(.shellCommandFailed("AppleScript (Select All & Copy)", -1, "Failed to execute the copy command. The frontmost application may not support it."))
    }
    
    try? await Task.sleep(for: .milliseconds(200))
    
    guard let copiedText = pasteboard.string(forType: .string), !copiedText.isEmpty else {
      return .failure(.unexpectedError("Could not retrieve text from the frontmost application. The clipboard was empty after copying."))
    }
    
    return .success(copiedText)
  }
  
    
  
    
  
   
  
      func getCurrentDateTime() -> Result<String, ToolExecutionError> {
  
          let date = Date()
  
          let formatter = DateFormatter()
  
          
  
          formatter.dateStyle = .full
  
          formatter.timeStyle = .long
  
          
  
          let dateTimeString = formatter.string(from: date)
  
          return .success(dateTimeString)
  
      }

  func runShellCommand(command: String) async -> Result<String, ToolExecutionError> {
    return await withCheckedContinuation { continuation in
      continuation.resume(returning: runShellCommandSync(command: command))
    }
  }
 
  private func runShellCommandSync(command: String) -> Result<String, ToolExecutionError> {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/bash")
    task.arguments = ["-c", command]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
     
      if task.terminationStatus == 0 {
        return .success(output.isEmpty ? "Command executed successfully. No output." : "Command output: \(output)")
      } else {
        return .failure(.shellCommandFailed(command, Int(task.terminationStatus), output))
      }
    } catch {
      return .failure(.unexpectedError("Shell Command Execution Error: \(error.localizedDescription)"))
    }
  }
 
  func takeScreenshot() async -> Result<String, ToolExecutionError> {
    return await withCheckedContinuation { continuation in
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
     
      // Arguments:
      // -c: Copy the screenshot to the clipboard
      // -x: Do not play capture sound
      // -C: Capture the cursor as well
      task.arguments = ["-c", "-x", "-C"]

      let pipe = Pipe()
      task.standardError = pipe

      task.terminationHandler = { process in
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
       
        if process.terminationStatus == 0 {
          continuation.resume(returning: .success("Successfully captured the full screen to the clipboard."))
        } else {
          continuation.resume(returning: .failure(.shellCommandFailed("/usr/sbin/screencapture", Int(process.terminationStatus), errorOutput)))
        }
      }

      do {
        try task.run()
      } catch {
        continuation.resume(returning: .failure(.unexpectedError("Screenshot Process Execution Error: \(error.localizedDescription)")))
      }
    }
  }


  func setSystemVolume(level: Int) async -> Result<String, ToolExecutionError> {
    guard 0 <= level && level <= 100 else {
      return .failure(.invalidArgument("Volume level must be between 0 and 100."))
    }
    let script = "set volume output volume \(level)"
    return await executeAppleScript(script)
  }

  func createFileWithContent(path: String, content: String) throws -> Result<String, ToolExecutionError> {
    let expandedPath = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expandedPath)
   
    let directoryURL = url.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      try content.write(to: url, atomically: true, encoding: .utf8)
      return .success("Successfully created file at: \(expandedPath)")
    } catch {
      return .failure(.fileOperationFailed(error.localizedDescription))
    }
  }

  func searchYouTube(query: String) -> Result<String, ToolExecutionError> {
    guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let url = URL(string: "https://www.youtube.com/results?search_query=\(encodedQuery)") else {
      return .failure(.invalidArgument("Invalid search query or URL."))
    }
   
    NSWorkspace.shared.open(url)
    return .success("Opened default web browser to search YouTube for: '\(query)'.")
  }
 
  func googleSearch(query: String) -> Result<String, ToolExecutionError> {
    guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") else {
      return .failure(.invalidArgument("Invalid search query or URL."))
    }
   
    NSWorkspace.shared.open(url)
    return .success("Opened default web browser to search Google for: '\(query)'.")
  }

  func openWebsite(url: String) -> Result<String, ToolExecutionError> {
    var normalizedUrl = url
    if !normalizedUrl.lowercased().hasPrefix("http") {
      normalizedUrl = "https://\(normalizedUrl)"
    }
   
    guard let urlObject = URL(string: normalizedUrl) else {
      return .failure(.invalidArgument("The provided URL is invalid: \(url)"))
    }
   
    NSWorkspace.shared.open(urlObject)
    return .success("Successfully opened the website: \(url)")
  }
}

