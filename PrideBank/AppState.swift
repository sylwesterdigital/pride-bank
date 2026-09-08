import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Stage: Equatable {
        case splash
        case welcome
        case identity
        case createPIN
        case confirmPIN
        case locked
        case unlocked
    }

    @Published var stage: Stage = .splash
    @Published var displayName = ""
    @Published var username = ""
    @Published var pendingPIN = ""
    @Published var pinError: String?
    @Published var selectedTab: MainTab = .home

    let blocksBalance = 12_480
    let recentActivity: [ActivityItem] = [
        .init(title: "3D Building Pack", subtitle: "Shop", amount: -350),
        .init(title: "From @Alex", subtitle: "Received", amount: 500),
        .init(title: "World access", subtitle: "Gallery World", amount: -80),
        .init(title: "Texture Pack sale", subtitle: "Creator", amount: 120)
    ]

    private let defaults = UserDefaults.standard
    private let pinStore = SecurePINStore()

    init() {
        displayName = defaults.string(forKey: "identity.displayName") ?? ""
        username = defaults.string(forKey: "identity.username") ?? ""

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1050))
            finishSplash()
        }
    }

    var isOnboarded: Bool {
        !displayName.isEmpty && !username.isEmpty && pinStore.hasPIN
    }

    func finishSplash() {
        stage = isOnboarded ? .locked : .welcome
    }

    func beginOnboarding() {
        stage = .identity
    }

    func saveIdentity(name: String, username rawUsername: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = rawUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }

        guard !cleanName.isEmpty, stripped.count >= 3 else { return }
        displayName = cleanName
        username = "@\(stripped)"
        defaults.set(cleanName, forKey: "identity.displayName")
        defaults.set(username, forKey: "identity.username")
        stage = .createPIN
    }

    func acceptNewPIN(_ pin: String) {
        guard pin.count == 6 else { return }
        pendingPIN = pin
        pinError = nil
        stage = .confirmPIN
    }

    func confirmNewPIN(_ pin: String) {
        guard pin.count == 6 else { return }
        guard pin == pendingPIN else {
            pendingPIN = ""
            pinError = "PINs did not match. Create it again."
            stage = .createPIN
            return
        }

        do {
            try pinStore.save(pin: pin)
            pendingPIN = ""
            pinError = nil
            stage = .locked
        } catch {
            pendingPIN = ""
            pinError = "PIN could not be saved securely."
            stage = .createPIN
        }
    }

    @discardableResult
    func unlock(with pin: String) -> Bool {
        guard pin.count == 6 else { return false }
        guard pinStore.verify(pin: pin) else {
            pinError = "Incorrect PIN"
            return false
        }
        pinError = nil
        stage = .unlocked
        return true
    }

    func lockIfNeeded() {
        if stage == .unlocked {
            stage = .locked
            selectedTab = .home
        }
    }

    func resetDemo() {
        defaults.removeObject(forKey: "identity.displayName")
        defaults.removeObject(forKey: "identity.username")
        pinStore.clear()
        displayName = ""
        username = ""
        pendingPIN = ""
        pinError = nil
        selectedTab = .home
        stage = .welcome
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case blocks = "Blocks"
    case shop = "Shop"
    case worlds = "Worlds"
    case profile = "Profile"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .blocks: return "square.stack.3d.up.fill"
        case .shop: return "bag.fill"
        case .worlds: return "sparkles"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let amount: Int
}
