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
        case cancelled, appleNotConfigured, googleNotConfigured, failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled:             nil
            case .appleNotConfigured:    "Sign in with Apple isn't enabled in this build. It needs the Sign in with Apple capability, which requires a paid Apple Developer account."
            case .googleNotConfigured:   "Google sign-in isn't set up in this build yet."
            case .failed(let reason):    reason
            }
        }
    }

    // MARK: Configuration

    /// True only when this build actually carries the Sign in with Apple capability. Apple grants
    /// that capability to paid Apple Developer accounts; the open build ships without it, so the
    /// Apple button is disabled instead of letting Apple reject the request on someone's phone.
    /// Enable it by flipping `AppleSignInEnabled` in `project.yml` at the same time as adding the
    /// entitlement (see docs/CODEBASE_OVERVIEW.md, §2).
    static var isAppleConfigured: Bool {
        switch Bundle.main.object(forInfoDictionaryKey: "AppleSignInEnabled") {
        case let flag as Bool:   return flag
        case let text as String: return ["yes", "true", "1"].contains(text.lowercased())
        default:                 return false
        }
    }

    /// At least one provider can complete a sign-in in this build. Used to avoid presenting a
    /// sign-in screen that has no working button on it.
    static var canSignIn: Bool { isAppleConfigured || isGoogleConfigured }

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
            guard let authError = error as? ASAuthorizationError else {
                throw AuthError.failed(error.localizedDescription)
            }
            switch authError.code {
            case .canceled:
                throw AuthError.cancelled
            case .unknown, .notHandled, .invalidResponse:
                // Without the capability Apple fails before showing its sheet; `.unknown` (1000) is
                // the usual "this app isn't provisioned for Sign in with Apple" response.
                if !isAppleConfigured { throw AuthError.appleNotConfigured }
                throw AuthError.failed(authError.localizedDescription)
            case .notInteractive:
                throw AuthError.failed("Sign in with Apple has to be started from inside OneTake.")
            case .failed:
                throw AuthError.failed(authError.localizedDescription)
            @unknown default:
                throw AuthError.failed(authError.localizedDescription)
            }
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
        guard isGoogleConfigured else { throw AuthError.googleNotConfigured }
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

    static func deleteAccount(_ account: Account?) {
        if account?.provider == .google {
            GIDSignIn.sharedInstance.disconnect()
        }
        signOut(account)
    }

    /// Apple can revoke the app's access (Settings → Apple ID → Sign in with Apple). Checked on
    /// launch so a revoked account doesn't stay signed in.
    static func isStillValid(_ account: Account) async -> Bool {
        // Without the capability Apple can't answer; keep the stored account rather than signing
        // someone out because of how this particular build was provisioned.
        guard account.provider == .apple, isAppleConfigured else { return true }
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
