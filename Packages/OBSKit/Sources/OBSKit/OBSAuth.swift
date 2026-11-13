import CryptoKit
import Foundation

/// The obs-websocket v5 authentication string.
///
/// secret = base64(sha256(password + salt)); auth = base64(sha256(secret + challenge)).
/// The password never goes over the socket; only this derived string does.
public enum OBSAuth {
    public static func authString(password: String, salt: String, challenge: String) -> String {
        let secret = base64SHA256(password + salt)
        return base64SHA256(secret + challenge)
    }

    private static func base64SHA256(_ text: String) -> String {
        Data(SHA256.hash(data: Data(text.utf8))).base64EncodedString()
    }
}
