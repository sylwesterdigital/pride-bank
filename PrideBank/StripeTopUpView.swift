import SwiftUI
import StripePaymentSheet

struct AddBlocksView: View {
    @EnvironmentObject private var appState: AppState
    @State private var packages:[BlocksPackage]=[]
    @State private var paymentSheet:PaymentSheet?
    @State private var showingPaymentSheet=false
    @State private var topupId:String?
    @State private var statusMessage:String?
    @State private var busy=false

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if packages.isEmpty && busy { ProgressView() }
            ForEach(packages) { pack in
                Button { Task { await prepare(pack) } } label: {
                    HStack {
                        Text(pack.label).fontWeight(.semibold)
                        Spacer()
                        Text(price(pack)).foregroundStyle(PrideTheme.secondary)
                    }.padding(16).background(PrideTheme.card,in:RoundedRectangle(cornerRadius:16,style:.continuous))
                }.buttonStyle(.plain).disabled(busy)
            }
            if let statusMessage { Text(statusMessage).font(.footnote).foregroundStyle(PrideTheme.secondary) }
            Text("Payments are processed by Stripe for WORKWORK.FUN LTD. Blocks are added only after Pride receives verified payment confirmation from Stripe.")
                .font(.caption).foregroundStyle(PrideTheme.secondary).padding(.top,6)
        }
        .task { await loadPackages() }
        .paymentSheet(isPresented:$showingPaymentSheet,paymentSheet:paymentSheet,onCompletion:paymentCompleted)
    }

    private func loadPackages() async {
        guard let token=appState.sessionToken else { statusMessage="Your account session is unavailable."; return }
        busy=true
        do { packages=try await APIClient.shared.packages(token:token).packages }
        catch { statusMessage=error.localizedDescription }
        busy=false
    }

    private func prepare(_ pack:BlocksPackage) async {
        guard let token=appState.sessionToken else { return }
        busy=true; statusMessage=nil
        do {
            let intent=try await APIClient.shared.createTopUp(packageId:pack.id,token:token,key:UUID().uuidString)
            StripeAPI.defaultPublishableKey=intent.publishableKey
            var config=PaymentSheet.Configuration(); config.merchantDisplayName="WORKWORK.FUN LTD"; config.allowsDelayedPaymentMethods=false
            paymentSheet=PaymentSheet(paymentIntentClientSecret:intent.clientSecret,configuration:config)
            topupId=intent.topupId; showingPaymentSheet=true
        } catch { statusMessage=error.localizedDescription }
        busy=false
    }

    private func paymentCompleted(_ result:PaymentSheetResult) {
        switch result {
        case .completed:
            statusMessage="Payment submitted. Verifying with Stripe…"
            Task { await awaitServerCredit() }
        case .canceled: statusMessage="Payment canceled."
        case .failed(let error): statusMessage=error.localizedDescription
        }
    }

    private func awaitServerCredit() async {
        guard let token=appState.sessionToken, let id=topupId else { return }
        for _ in 0..<12 {
            do {
                let state=try await APIClient.shared.topUpStatus(id:id,token:token)
                if state.status == "succeeded" { statusMessage="\(state.blocks_amount.formatted()) Blocks added."; await appState.refreshAccount(); return }
                if ["failed","canceled","refunded"].contains(state.status) { statusMessage="Payment status: \(state.status)."; return }
            } catch { statusMessage=error.localizedDescription; return }
            try? await Task.sleep(for:.seconds(1))
        }
        statusMessage="Payment is still being verified. Your balance will update after Stripe confirmation."
    }

    private func price(_ pack:BlocksPackage)->String {
        let value=Double(pack.amount)/100.0
        return value.formatted(.currency(code:pack.currency.uppercased()))
    }
}
