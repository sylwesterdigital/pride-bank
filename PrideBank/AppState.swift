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
    @Published var stage:Stage = .splash
    @Published var displayName=""; @Published var username=""; @Published var email=""
    @Published var pendingPIN=""; @Published var pinError:String?; @Published var accountError:String?
    @Published var selectedTab:MainTab = .home
    @Published var blocksBalance=0; @Published var recentActivity:[ActivityItem]=[]
    @Published var isBusy=false

    private let defaults=UserDefaults.standard
    private let pinStore=SecurePINStore(); private let sessionStore=SecureSessionStore()

    init(){
        displayName=defaults.string(forKey:"identity.displayName") ?? ""; username=defaults.string(forKey:"identity.username") ?? ""; email=defaults.string(forKey:"identity.email") ?? ""
        Task { try? await Task.sleep(for:.milliseconds(900)); finishSplash() }
    }
    var isOnboarded:Bool { !displayName.isEmpty && !username.isEmpty && pinStore.hasPIN && sessionStore.load() != nil }
    var sessionToken:String? { sessionStore.load() }
    func finishSplash(){ stage=isOnboarded ? .locked : .welcome }
    func beginOnboarding(){ accountError=nil; stage = .identity }

    func createAccount(name:String, username raw:String, email:String, password:String) async {
        let cleanName=name.trimmingCharacters(in:.whitespacesAndNewlines); let cleanUsername=raw.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"@",with:"").lowercased()
        guard cleanName.count>=2, cleanUsername.count>=3, email.contains("@"), password.count>=12 else { accountError="Complete all account details. Password must be at least 12 characters."; return }
        isBusy=true; accountError=nil
        do {
            let response=try await APIClient.shared.register(email:email,username:cleanUsername,displayName:cleanName,password:password)
            try sessionStore.save(response.token)
            displayName=response.user.display_name; username="@\(response.user.username)"; self.email=response.user.email
            defaults.set(displayName,forKey:"identity.displayName"); defaults.set(username,forKey:"identity.username"); defaults.set(self.email,forKey:"identity.email")
            stage = .createPIN
        } catch { accountError=error.localizedDescription }
        isBusy=false
    }
    func acceptNewPIN(_ pin:String){ guard pin.count==6 else{return}; pendingPIN=pin; pinError=nil; stage = .confirmPIN }
    func confirmNewPIN(_ pin:String){
        guard pin.count==6 else{return}; guard pin==pendingPIN else { pendingPIN=""; pinError="PINs did not match."; stage = .createPIN; return }
        do { try pinStore.save(pin:pin); pendingPIN=""; stage = .locked } catch { pinError="PIN could not be saved securely."; stage = .createPIN }
    }
    @discardableResult func unlock(with pin:String)->Bool {
        guard pin.count==6,pinStore.verify(pin:pin),sessionStore.load() != nil else { pinError="Incorrect PIN or account session unavailable"; return false }
        pinError=nil; stage = .unlocked; Task{ await refreshAccount() }; return true
    }
    func refreshAccount() async {
        guard let token=sessionStore.load() else { return }
        do {
            async let me=APIClient.shared.me(token:token); async let activity=APIClient.shared.activity(token:token)
            let (m,a)=try await (me,activity); displayName=m.user.display_name; username="@\(m.user.username)"; email=m.user.email; blocksBalance=m.blocksBalance
            recentActivity=a.items.map{ ActivityItem(id:$0.id,title:$0.description.isEmpty ? $0.kind : $0.description,subtitle:$0.kind,amount:$0.amount) }
        } catch { accountError=error.localizedDescription }
    }
    func lockIfNeeded(){ if stage == .unlocked { stage = .locked; selectedTab = .home } }
    func resetAccount(){ defaults.removePersistentDomain(forName:Bundle.main.bundleIdentifier ?? ""); pinStore.clear(); sessionStore.clear(); displayName=""; username=""; email=""; blocksBalance=0; recentActivity=[]; stage = .welcome }
}

enum MainTab:String,CaseIterable,Identifiable { case home="Home",blocks="Blocks",shop="Shop",worlds="Worlds",profile="Profile"; var id:String{rawValue}; var icon:String{ switch self {case .home:return "house.fill";case .blocks:return "square.stack.3d.up.fill";case .shop:return "bag.fill";case .worlds:return "sparkles";case .profile:return "person.crop.circle.fill"} } }
struct ActivityItem:Identifiable { let id:String; let title:String; let subtitle:String; let amount:Int }
