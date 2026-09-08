import Foundation

struct APIUser: Codable { let id:String; let email:String; let username:String; let display_name:String; let status:String? }
struct AuthResponse: Codable { let user:APIUser; let token:String }
struct MeResponse: Codable { let user:APIUser; let blocksBalance:Int }
struct ActivityResponse: Codable { let items:[APIActivity] }
struct APIActivity: Codable, Identifiable { let id:String; let kind:String; let description:String; let created_at:String; let amount:Int }
struct BlocksPackage: Codable, Identifiable { let id:String; let blocks:Int; let amount:Int; let currency:String; let label:String }
struct PackageResponse: Codable { let currency:String; let merchant:String; let packages:[BlocksPackage] }
struct TopUpIntent: Codable { let topupId:String; let clientSecret:String; let publishableKey:String; let status:String }
struct TopUpStatus: Codable { let id:String; let blocks_amount:Int; let fiat_amount:Int; let currency:String; let status:String }

actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let session = URLSession(configuration: .ephemeral)

    private var baseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey:"PRIDEAPIBaseURL") as? String,
              !raw.contains("$("), let url=URL(string:raw.trimmingCharacters(in:.whitespacesAndNewlines)) else {
            fatalError("PRIDEAPIBaseURL is not configured")
        }
        return url
    }

    func register(email:String, username:String, displayName:String, password:String) async throws -> AuthResponse {
        try await request("v1/auth/register",method:"POST",body:["email":email,"username":username,"displayName":displayName,"password":password],token:nil)
    }
    func me(token:String) async throws -> MeResponse { try await request("v1/me",token:token) }
    func activity(token:String) async throws -> ActivityResponse { try await request("v1/blocks/activity",token:token) }
    func packages(token:String) async throws -> PackageResponse { try await request("v1/blocks/packages",token:token) }
    func createTopUp(packageId:String, token:String, key:String) async throws -> TopUpIntent {
        try await request("v1/blocks/topups/payment-intent",method:"POST",body:["packageId":packageId],token:token,headers:["Idempotency-Key":key])
    }
    func topUpStatus(id:String, token:String) async throws -> TopUpStatus { try await request("v1/blocks/topups/\(id)",token:token) }

    private func request<T:Decodable>(_ path:String, method:String="GET", body:[String:String]?=nil, token:String?, headers:[String:String]=[:]) async throws -> T {
        var req=URLRequest(url:baseURL.appending(path:path)); req.httpMethod=method; req.timeoutInterval=20
        req.setValue("application/json",forHTTPHeaderField:"Accept")
        if let token { req.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
        for (k,v) in headers { req.setValue(v,forHTTPHeaderField:k) }
        if let body { req.setValue("application/json",forHTTPHeaderField:"Content-Type"); req.httpBody=try encoder.encode(body) }
        let (data,response)=try await session.data(for:req)
        guard let http=response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message=(try? JSONSerialization.jsonObject(with:data) as? [String:Any])?["message"] as? String
            throw NSError(domain:"PrideAPI",code:http.statusCode,userInfo:[NSLocalizedDescriptionKey:message ?? "Request failed"])
        }
        return try decoder.decode(T.self,from:data)
    }
}
