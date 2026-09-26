// Exports one code-signing identity (certificate + private key) from the login keychain as a
// password-protected .p12, without opening Keychain Access. macOS asks once to allow key access.
//   export-identity "<name prefix>" <output.p12> <password>
import Foundation
import Security

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 else { fail("usage: export-identity \"<name prefix>\" <output.p12> <password>") }
let prefix = arguments[arguments.startIndex]
let output = URL(fileURLWithPath: arguments[arguments.startIndex + 1])
let password = arguments[arguments.startIndex + 2]

var result: CFTypeRef?
let status = SecItemCopyMatching([
    kSecClass: kSecClassIdentity,
    kSecMatchLimit: kSecMatchLimitAll,
    kSecReturnRef: true,
] as CFDictionary, &result)
guard status == errSecSuccess, let identities = result as? [SecIdentity] else { fail("no identities found (OSStatus \(status))") }

let matches: [(identity: SecIdentity, name: String)] = identities.compactMap { identity in
    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
          let name = SecCertificateCopySubjectSummary(certificate) as String?, name.hasPrefix(prefix) else { return nil }
    return (identity, name)
}
guard let match = matches.first else { fail("no identity named \"\(prefix)…\" in the keychain") }
guard matches.count == 1 else { fail("\(matches.count) identities match \"\(prefix)…\"; use a longer prefix") }
let identity = match.identity

var parameters = SecItemImportExportKeyParameters()
parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
parameters.passphrase = Unmanaged.passRetained(password as CFString)
var data: CFData?
let exportStatus = SecItemExport(identity, .formatPKCS12, [], &parameters, &data)
guard exportStatus == errSecSuccess, let data else { fail("export failed (OSStatus \(exportStatus))") }
do {
    try (data as Data).write(to: output, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
} catch { fail("could not write \(output.path): \(error.localizedDescription)") }
print("exported \(match.name)")
