import SwiftUI
import StripePaymentSheet

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            PrideTheme.background.ignoresSafeArea()
            switch appState.stage {
            case .splash:
                SplashView()
            case .welcome:
                WelcomeView()
            case .identity:
                IdentityView()
            case .createPIN:
                PINEntryView(mode: .create)
            case .confirmPIN:
                PINEntryView(mode: .confirm)
            case .locked:
                PINEntryView(mode: .unlock)
            case .unlocked:
                MainAppView()
            }
        }
        .animation(.easeInOut(duration: 0.24), value: appState.stage)
    }
}

private struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            BlockMark(size: 58)
                .scaleEffect(appeared ? 1 : 0.82)
                .opacity(appeared ? 1 : 0)
            Text("PRIDE")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .tracking(5)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { appeared = true }
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            BlockMark(size: 44)
                .padding(.bottom, 28)
            Text("Welcome to Pride")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .tracking(-1.2)
            Text("Create, explore and participate using Blocks.")
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .foregroundStyle(PrideTheme.secondary)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Get started") { appState.beginOnboarding() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 26)
    }
}

private struct IdentityView: View {
    @EnvironmentObject private var appState: AppState
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    private var canContinue: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        username.replacingOccurrences(of: "@", with: "").count >= 3 &&
        email.contains("@") && password.count >= 12
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Create your Pride account")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Your account holds your identity, Blocks balance and transaction history securely on Pride.")
                    .font(.system(size: 17, design: .rounded))
                    .foregroundStyle(PrideTheme.secondary)
                    .padding(.top, 10)

                VStack(spacing: 12) {
                    accountField("Display name", text: $name, secure: false, keyboard: .default)
                    accountField("Username", text: $username, secure: false, keyboard: .default)
                    accountField("Email", text: $email, secure: false, keyboard: .emailAddress)
                    accountField("Password (12+ characters)", text: $password, secure: true, keyboard: .default)
                }.padding(.top, 28)

                if let error = appState.accountError {
                    Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(.red.opacity(0.9)).padding(.top, 12)
                }

                Button(appState.isBusy ? "Creating account…" : "Continue") {
                    Task { await appState.createAccount(name: name, username: username, email: email, password: password) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue || appState.isBusy)
                .opacity(canContinue && !appState.isBusy ? 1 : 0.45)
                .padding(.top, 28)
            }
            .padding(.horizontal, 24).padding(.vertical, 30)
        }
    }

    @ViewBuilder
    private func accountField(_ title: String, text: Binding<String>, secure: Bool, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(PrideTheme.secondary)
            Group {
                if secure { SecureField(title, text: text) } else { TextField(title, text: text) }
            }
            .keyboardType(keyboard).textInputAutocapitalization(title == "Display name" ? .words : .never).autocorrectionDisabled()
            .font(.system(size: 18, weight: .medium, design: .rounded)).padding(.horizontal, 17).frame(height: 58)
            .background(PrideTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
private struct PINEntryView: View {
    enum Mode { case create, confirm, unlock }

    @EnvironmentObject private var appState: AppState
    let mode: Mode
    @State private var pin = ""
    @State private var shake = false

    private var title: String {
        switch mode {
        case .create: return "Create a PIN"
        case .confirm: return "Confirm your PIN"
        case .unlock: return appState.displayName.isEmpty ? "Welcome back" : "Good evening, \(appState.displayName)"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create: return "Use 6 digits to protect access to your Blocks."
        case .confirm: return "Enter the same 6 digits again."
        case .unlock: return "Enter your PIN to continue."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            if mode == .unlock {
                avatar
                    .padding(.bottom, 20)
            }

            Text(title)
                .font(.system(size: mode == .unlock ? 19 : 31, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(PrideTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            HStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.top, 32)
            .offset(x: shake ? 8 : 0)

            if let error = appState.pinError {
                Text(error)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.top, 14)
            }

            Spacer()

            PINPad(pin: $pin) { completed in
                handle(completed)
            }
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 28)
        .onAppear {
            appState.pinError = nil
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.14))
            Text(initials(appState.displayName))
                .font(.system(size: 19, weight: .bold, design: .rounded))
        }
        .frame(width: 58, height: 58)
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func handle(_ completed: String) {
        switch mode {
        case .create:
            appState.acceptNewPIN(completed)
        case .confirm:
            appState.confirmNewPIN(completed)
        case .unlock:
            if !appState.unlock(with: completed) {
                withAnimation(.easeInOut(duration: 0.08).repeatCount(3, autoreverses: true)) {
                    shake.toggle()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    pin = ""
                    shake = false
                }
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

private struct PINPad: View {
    @Binding var pin: String
    let onComplete: (String) -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "delete"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { value in
                        keypadButton(value)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keypadButton(_ value: String) -> some View {
        if value.isEmpty {
            Color.clear.frame(maxWidth: .infinity).frame(height: 66)
        } else {
            Button {
                if value == "delete" {
                    if !pin.isEmpty { pin.removeLast() }
                } else if pin.count < 6 {
                    pin.append(value)
                    if pin.count == 6 {
                        let complete = pin
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { onComplete(complete) }
                    }
                }
            } label: {
                Group {
                    if value == "delete" {
                        Image(systemName: "delete.left")
                    } else {
                        Text(value)
                    }
                }
                .font(.system(size: 25, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct MainAppView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView().tag(MainTab.home)
            BlocksView().tag(MainTab.blocks)
            ShopView().tag(MainTab.shop)
            WorldsView().tag(MainTab.worlds)
            ProfileView().tag(MainTab.profile)
        }
        .tint(.white)
    }
}

private struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var action: QuickAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    balanceCard
                    activityCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 26)
            }
            .background(PrideTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $action) { item in
            QuickActionSheet(action: item)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            BlockMark(size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Good evening")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(PrideTheme.secondary)
                Text(appState.displayName)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
            }
            Spacer()
            Circle()
                .fill(Color.white.opacity(0.13))
                .frame(width: 42, height: 42)
                .overlay(Text(String(appState.displayName.prefix(1)).uppercased()).font(.headline))
        }
        .padding(.top, 10)
    }

    private var balanceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 20) {
                Text("Blocks")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PrideTheme.secondary)
                Text(appState.blocksBalance.formatted())
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                HStack(spacing: 10) {
                    actionButton("Send", icon: "arrow.up", action: .send)
                    actionButton("Request", icon: "arrow.down", action: .request)
                    actionButton("Add", icon: "plus", action: .add)
                }
            }
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent activity")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                Text("See all")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PrideTheme.secondary)
            }
            VStack(spacing: 0) {
                ForEach(appState.recentActivity) { item in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.09))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: item.amount > 0 ? "arrow.down.left" : "cube.fill").font(.system(size: 15, weight: .semibold)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(item.subtitle).font(.system(size: 13, design: .rounded)).foregroundStyle(PrideTheme.secondary)
                        }
                        Spacer()
                        Text((item.amount > 0 ? "+" : "") + item.amount.formatted())
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(item.amount > 0 ? Color.green.opacity(0.9) : .white)
                    }
                    .padding(.vertical, 11)
                    if item.id != appState.recentActivity.last?.id {
                        Divider().overlay(Color.white.opacity(0.07))
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action selected: QuickAction) -> some View {
        Button { action = selected } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(PrideTheme.cardStrong)
                    .frame(width: 46, height: 46)
                    .overlay(Image(systemName: icon).font(.system(size: 17, weight: .bold)))
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private enum QuickAction: String, Identifiable {
    case send = "Send Blocks"
    case request = "Request Blocks"
    case add = "Add Blocks"
    var id: String { rawValue }
}

private struct QuickActionSheet: View {
    let action: QuickAction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(action.rawValue)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                switch action {
                case .send:
                    TextField("@username", text: .constant(""))
                    TextField("Amount", text: .constant(""))
                        .keyboardType(.numberPad)
                    TextField("Note", text: .constant(""))
                case .request:
                    Text("Create a request for another member.")
                        .foregroundStyle(PrideTheme.secondary)
                case .add:
                    AddBlocksView()
                }
                Spacer()
            }
            .textFieldStyle(.roundedBorder)
            .padding(24)
            .background(Color.black.opacity(0.96).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

}

private struct BlocksView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Blocks balance").foregroundStyle(PrideTheme.secondary)
                        Text(appState.blocksBalance.formatted()).font(.system(size: 42, weight: .bold, design: .rounded))
                    }
                    .padding(.vertical, 12)
                }
                Section("Activity") {
                    ForEach(appState.recentActivity) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Text((item.amount > 0 ? "+" : "") + item.amount.formatted())
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PrideTheme.background.ignoresSafeArea())
            .navigationTitle("Blocks")
        }
    }
}

private struct ShopView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    product("Cyberpunk Building Pack", creator: "@Maya", price: 350, detail: "12 3D models · Textures included")
                    product("Studio Material Set", creator: "@Alex", price: 180, detail: "36 materials · 4K textures")
                }
                .padding(18)
            }
            .background(PrideTheme.background.ignoresSafeArea())
            .navigationTitle("Shop")
        }
    }

    private func product(_ title: String, creator: String, price: Int, detail: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [.purple.opacity(0.65), .blue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 170)
                    .overlay(Image(systemName: "cube.transparent.fill").font(.system(size: 54)).foregroundStyle(.white.opacity(0.8)))
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Created by \(creator)").foregroundStyle(PrideTheme.secondary)
                Text(detail).font(.footnote).foregroundStyle(PrideTheme.secondary)
                Text("\(price) Blocks").font(.system(size: 17, weight: .bold, design: .rounded)).padding(.top, 4)
            }
        }
    }
}

private struct WorldsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    world("Gallery World", detail: "Your creative space", badge: "Open")
                    world("Night City", detail: "Explore · 284 people", badge: "Enter")
                    world("Design Commons", detail: "Events today", badge: "Explore")
                }
                .padding(18)
            }
            .background(PrideTheme.background.ignoresSafeArea())
            .navigationTitle("Worlds")
        }
    }

    private func world(_ title: String, detail: String, badge: String) -> some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(detail).foregroundStyle(PrideTheme.secondary)
                }
                Spacer()
                Text(badge).font(.system(size: 13, weight: .semibold, design: .rounded)).padding(.horizontal, 13).padding(.vertical, 8).background(PrideTheme.cardStrong, in: Capsule())
            }
        }
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Circle().fill(Color.white.opacity(0.12)).frame(width: 58, height: 58).overlay(Text(String(appState.displayName.prefix(1)).uppercased()).font(.title2.bold()))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appState.displayName).font(.headline)
                            Text(appState.username).foregroundStyle(PrideTheme.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("Account") {
                    Label("Personal info", systemImage: "person.text.rectangle")
                    Label("Security", systemImage: "lock.fill")
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }
                Section {
                    Button("Lock app") { appState.lockIfNeeded() }
                    Button("Reset demo", role: .destructive) { appState.resetAccount() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PrideTheme.background.ignoresSafeArea())
            .navigationTitle("Profile")
        }
    }
}
