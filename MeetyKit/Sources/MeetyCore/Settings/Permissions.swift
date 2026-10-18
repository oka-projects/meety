import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// As duas permissões do Meety: microfone e gravação de tela (que no macOS inclui o áudio do sistema).
public enum Permissions {
    public enum State: Equatable, Sendable { case granted, denied, notDetermined }

    public static var microphone: State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    public static func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    /// Gravação de tela: `CGPreflightScreenCaptureAccess` diz se já foi dada.
    public static var screenRecording: State { CGPreflightScreenCaptureAccess() ? .granted : .notDetermined }

    /// Pede a permissão. Na primeira vez o macOS mostra o aviso; depois é preciso ligar nos Ajustes.
    @discardableResult
    public static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    /// Confere de verdade tentando listar o conteúdo compartilhável (o preflight às vezes mente).
    public static func probeScreenRecording() async -> Bool {
        do { _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true); return true }
        catch { return false }
    }

    public static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }
    public static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }
    static func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    public struct Microphone: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
    }

    public static func microphones() -> [Microphone] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        return session.devices.map { Microphone(id: $0.uniqueID, name: $0.localizedName) }
    }
}
