import CryptoKit
import Foundation
import Security
import SwiftUI
import UIKit

/// Optional Spotify remote (Web API). Nothing runs unless you connect in Settings.
/// Playback control needs Spotify Premium and Spotify open on some device.
@Observable
@MainActor
final class Spotify {
    static let shared = Spotify()
    static let redirect = "ironlog://spotify"

    var track: String?
    var isPlaying = false
    var playlists: [(name: String, uri: String)] = []
    var message: String?
    var isConnected: Bool { refreshToken != nil }

    /// From your free app at developer.spotify.com (entered in Settings).
    var clientId: String { (UserDefaults.standard.string(forKey: "spotify.clientId") ?? "").trimmingCharacters(in: .whitespaces) }
    private var refreshToken: String? = Keychain.get("spotify.refresh")
    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var expiry = Date.distantPast
    @ObservationIgnored private var verifier = ""

    // MARK: Connect

    /// URL for the Spotify login page (PKCE, no secret stored in the app).
    func authorizeURL() -> URL? {
        verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")
        c?.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirect),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: "user-read-playback-state user-modify-playback-state playlist-read-private"),
        ]
        return c?.url
    }

    func finishLogin(callback: URL) async {
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            message = "Spotify login was cancelled."
            return
        }
        await token(["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirect,
                     "code_verifier": verifier])
        await refresh()
    }

    func disconnect() {
        Keychain.set(nil, for: "spotify.refresh")
        refreshToken = nil
        accessToken = nil
        track = nil
        playlists = []
    }

    // MARK: Controls

    func refresh() async {
        guard isConnected else { return }
        if let json = await call("GET", "me/player") as? [String: Any] {
            isPlaying = json["is_playing"] as? Bool ?? false
            if let item = json["item"] as? [String: Any], let name = item["name"] as? String {
                let artist = ((item["artists"] as? [[String: Any]])?.first?["name"] as? String).map { " · \($0)" } ?? ""
                track = name + artist
            }
        } else {
            isPlaying = false
        }
        if playlists.isEmpty, let list = await call("GET", "me/playlists?limit=30") as? [String: Any] {
            playlists = (list["items"] as? [[String: Any]] ?? []).compactMap { item -> (name: String, uri: String)? in
                guard let name = item["name"] as? String, let uri = item["uri"] as? String else { return nil }
                return (name, uri)
            }
        }
    }

    func togglePlay() async { await control("PUT", isPlaying ? "me/player/pause" : "me/player/play") }
    func next() async { await control("POST", "me/player/next") }
    func previous() async { await control("POST", "me/player/previous") }

    func play(uri: String) async {
        let body = try? JSONSerialization.data(withJSONObject: ["context_uri": uri])
        await control("PUT", "me/player/play", body: body, fallback: URL(string: uri))
    }

    /// Sends a command; if no Spotify device is active, opens the Spotify app instead.
    private func control(_ method: String, _ path: String, body: Data? = nil, fallback: URL? = URL(string: "spotify:")) async {
        Haptics.tap()
        let status = await send(method, path, body: body)?.statusCode ?? 0
        if status == 404, let fallback {
            _ = await UIApplication.shared.open(fallback)
        } else if status == 403 {
            message = "Controls need Spotify Premium."
        }
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
    }

    // MARK: Networking

    private func call(_ method: String, _ path: String) async -> Any? {
        guard let result = await request(method, path, body: nil), result.1.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: result.0)
    }

    private func send(_ method: String, _ path: String, body: Data?) async -> HTTPURLResponse? {
        await request(method, path, body: body)?.1
    }

    private func request(_ method: String, _ path: String, body: Data?) async -> (Data, HTTPURLResponse)? {
        if accessToken == nil || expiry < .now, let refreshToken {
            await token(["grant_type": "refresh_token", "refresh_token": refreshToken])
        }
        guard let accessToken, let url = URL(string: "https://api.spotify.com/v1/" + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard let result = try? await URLSession.shared.data(for: req),
              let http = result.1 as? HTTPURLResponse else { return nil }
        return (result.0, http)
    }

    private func token(_ params: [String: String]) async {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = (params.merging(["client_id": clientId]) { a, _ in a })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        guard let data = try? await URLSession.shared.data(for: req).0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            message = "Couldn't reach Spotify. Check the Client ID and your internet."
            return
        }
        accessToken = access
        expiry = Date.now.addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 60)
        if let refresh = json["refresh_token"] as? String {
            refreshToken = refresh
            Keychain.set(refresh, for: "spotify.refresh")
        }
        message = nil
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Tiny Keychain wrapper for the Spotify login token.
enum Keychain {
    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                    kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Mini player bar

/// One slim row: song, previous / play-pause / next, playlist picker. Hidden unless connected.
struct SpotifyBar: View {
    private var spotify = Spotify.shared

    var body: some View {
        if spotify.isConnected {
            HStack(spacing: 4) {
                Menu {
                    ForEach(spotify.playlists, id: \.uri) { p in
                        Button(p.name) { Task { await spotify.play(uri: p.uri) } }
                    }
                } label: {
                    Image(systemName: "music.note.list").frame(width: 34, height: 34)
                }
                Text(spotify.message ?? spotify.track ?? "Pick a playlist")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                button("backward.fill") { await spotify.previous() }
                button(spotify.isPlaying ? "pause.fill" : "play.fill") { await spotify.togglePlay() }
                button("forward.fill") { await spotify.next() }
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(Theme.cardRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 4)
            .task {
                // Light polling only while the bar is on screen.
                while !Task.isCancelled {
                    await spotify.refresh()
                    try? await Task.sleep(for: .seconds(8))
                }
            }
        }
    }

    private func button(_ icon: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}
