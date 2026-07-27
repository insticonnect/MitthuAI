import Foundation
import AppKit

/// Pairs this device with a mitthuai account WITHOUT embedding Google OAuth in
/// the app. Login happens on the website ("manage from our side"):
///
///   1. App opens `https://mitthuai.com/pair?device_id=<id>&name=<host>` in the
///      browser.
///   2. User signs in with Google on the site; the site binds device_id → account.
///   3. App polls `GET <pairingURL>/api/device-token?device_id=<id>` until the
///      relay returns `{ "token": "<account token>" }`.
///   4. Token is saved to Keychain; the relay tunnel (RelayClient) starts.
///
/// No Gmail scopes, no tokens for anything but identity, nothing sensitive in
/// the app beyond the account token (kept in Keychain).
final class AccountPairing {
    static let shared = AccountPairing()

    private var polling = false
    var onPaired: (() -> Void)?

    var isPaired: Bool { Keychain.get("account_token")?.isEmpty == false }

    private func deviceId() -> String {
        if let id = Keychain.get("device_id") { return id }
        let id = UUID().uuidString
        Keychain.set("device_id", id)
        return id
    }

    /// Kick off pairing: open the browser and begin polling for the token.
    func begin() {
        let id = deviceId()
        let host = Host.current().localizedName ?? "Mac"
        var comps = URLComponents(string: Config.shared.pairingURL) ?? URLComponents()
        comps.path = "/pair"
        comps.queryItems = [
            URLQueryItem(name: "device_id", value: id),
            URLQueryItem(name: "name", value: host)
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
        startPolling(deviceId: id)
    }

    func signOut() {
        Keychain.set("account_token", nil)
        Config.shared.relayEnabled = false
        Config.shared.save()
    }

    private func startPolling(deviceId: String, attempt: Int = 0) {
        guard !polling || attempt > 0 else { return }
        polling = true
        // Poll for up to ~3 minutes.
        guard attempt < 60 else { polling = false; return }

        guard var comps = URLComponents(string: Config.shared.pairingURL) else { polling = false; return }
        comps.path = "/api/device-token"
        comps.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        guard let url = comps.url else { polling = false; return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self else { return }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["token"] as? String, !token.isEmpty {
                Keychain.set("account_token", token)
                Config.shared.relayEnabled = true
                Config.shared.save()
                self.polling = false
                DispatchQueue.main.async { self.onPaired?() }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                self.startPolling(deviceId: deviceId, attempt: attempt + 1)
            }
        }.resume()
    }
}
