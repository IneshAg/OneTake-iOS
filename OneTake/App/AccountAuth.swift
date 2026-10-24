import AuthenticationServices
import GoogleSignIn
import UIKit

/// Who's signed in, if anyone. OneTake works fully as a guest; an account is only asked for where
/// one is genuinely needed (sending a tape as a link). Apple and Google each verify the person, and
/// either one signs up a new person or signs back in an existing one — there's no separate sign-up.
struct Account: Codable, Hashable {
    enum Provider: String, Codable, Hashable { case apple, google }
    var provider: Provider
    /// The provider's stable user identifier.
    var userID: String
    var name: String?
    var email: String?

    var providerName: String { provider == .apple ? "Apple" : "Google" }
}

enum AccountAuth {
    enum AuthError: LocalizedError {
        case cancelled, notConfigured, failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled:          nil
            case .notConfigured:      "Google sign-in isn't set up in this build yet."
            case .failed(let reason): reason
            }
        }
    }

    // MARK: Apple

    /// Builds the account from a completed Sign in with Apple. Apple only shares the name and email
    /// the first time someone signs up, so `previous` keeps them on later sign-ins.
    static func account(from result: Result<ASAuthorization, Error>, previous: Account?) throws -> Account {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthError.failed("Apple didn't return an account.")
            }
            let name = credential.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
            let sameUser = previous?.provider == .apple && previous?.userID == credential.user
            return Account(provider: .apple, userID: credential.user,
                           name: name ?? (sameUser ? previous?.name : nil),
                           email: credential.email ?? (sameUser ? previous?.email : nil))
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { throw AuthError.cancelled }
            throw AuthError.failed(error.localizedDescription)
        }
    }

    // MARK: Google

    /// Google needs an OAuth client ID (GIDClientID in Info.plist, from project.yml). Without a real
    /// one the SDK would crash, so the button is disabled until it's configured.
    static var isGoogleConfigured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return id.hasSuffix(".apps.googleusercontent.com") && !id.hasPrefix("YOUR_")
    }

    @MainActor
    static func signInWithGoogle() async throws -> Account {
        guard isGoogleConfigured else { throw AuthError.notConfigured }
        guard let presenter = topViewController() else { throw AuthError.failed("Couldn't show Google sign-in.") }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            let user = result.user
            return Account(provider: .google, userID: user.userID ?? user.profile?.email ?? UUID().uuidString,
                           name: user.profile?.name, email: user.profile?.email)
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
            throw AuthError.cancelled
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }
    }

    // MARK: Session

    static func signOut(_ account: Account?) {
        if account?.provider == .google { GIDSignIn.sharedInstance.signOut() }
    }

    /// Apple can revoke the app's access (Settings → Apple ID → Sign in with Apple). Checked on
    /// launch so a revoked account doesn't stay signed in.
    static func isStillValid(_ account: Account) async -> Bool {
        guard account.provider == .apple else { return true }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: account.userID)
        return state != .revoked && state != .notFound
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
