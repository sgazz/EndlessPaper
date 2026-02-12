//
//  CanvasSessionManager.swift
//  InfinityPaper
//
//  Manages session persistence (save/load) and autosave behavior for the canvas.
//

import Foundation
import UIKit
import OSLog

/// Manages session persistence and autosave behavior.
final class CanvasSessionManager {
    private let logger = Logger(subsystem: "com.infinitypaper", category: "Session")
    private var periodicSaveTimer: Timer?
    
    private enum SessionKeys {
        static let autosaveMode = "settings.session.autosaveMode"
        static let autoloadOnLaunch = "settings.session.autoload"
    }
    
    private static let periodicSaveInterval: TimeInterval = 60
    
    /// Checks if session should be automatically loaded on launch.
    func shouldAutoloadOnLaunch() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SessionKeys.autoloadOnLaunch) != nil else { return true }
        return defaults.bool(forKey: SessionKeys.autoloadOnLaunch)
    }
    
    /// Gets the current autosave mode.
    func currentAutosaveMode() -> AutosaveMode {
        let raw = UserDefaults.standard.string(forKey: SessionKeys.autosaveMode)
            ?? AutosaveMode.onBackground.rawValue
        return AutosaveMode(rawValue: raw) ?? .onBackground
    }
    
    /// Saves a session to disk.
    /// - Parameters:
    ///   - session: The session to save
    ///   - completion: Called with success or error
    func saveSession(_ session: StoredSession, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let data = try SessionPersistence.encode(session)
            try data.write(to: SessionPersistence.sessionURL(), options: Data.WritingOptions.atomic)
            completion(.success(()))
        } catch {
            logger.error("Session save failed: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    /// Loads a session from disk.
    /// - Parameter completion: Called with the loaded session or error
    func loadSession(completion: @escaping (Result<StoredSession, Error>) -> Void) {
        do {
            let data = try Data(contentsOf: SessionPersistence.sessionURL())
            let session = try SessionPersistence.decode(from: data)
            completion(.success(session))
        } catch {
            logger.debug("Session load skipped or failed: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    /// Deletes the session file from disk.
    func deleteSession() {
        try? FileManager.default.removeItem(at: SessionPersistence.sessionURL())
    }
    
    /// Starts periodic save timer if autosave mode is set to periodic.
    /// - Parameter saveCallback: Called when timer fires to trigger a save
    func startPeriodicSaveTimerIfNeeded(saveCallback: @escaping () -> Void) {
        stopPeriodicSaveTimer()
        guard currentAutosaveMode() == .periodic else { return }
        
        let timer = Timer.scheduledTimer(withTimeInterval: Self.periodicSaveInterval, repeats: true) { _ in
            saveCallback()
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicSaveTimer = timer
    }
    
    /// Stops the periodic save timer.
    func stopPeriodicSaveTimer() {
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
    }
    
    /// Registers for app lifecycle notifications and calls callbacks.
    /// - Parameters:
    ///   - saveOnResign: Called when app will resign active (for background save)
    ///   - resumeOnActive: Called when app becomes active (to restart timer)
    func registerForAppLifecycle(
        saveOnResign: @escaping () -> Void,
        resumeOnActive: @escaping () -> Void
    ) {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            saveOnResign()
            self?.stopPeriodicSaveTimer()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            resumeOnActive()
        }
    }
    
    /// Removes all observers (call in deinit or when manager is no longer needed).
    func unregisterFromAppLifecycle() {
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        stopPeriodicSaveTimer()
        unregisterFromAppLifecycle()
    }
}

