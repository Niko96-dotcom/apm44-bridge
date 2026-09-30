#!/usr/bin/xcrun swift
// Verify-only stand-in for Sparkle's `sign_update --verify` that needs only
// the public Ed25519 key, so verification never has to hold the private
// signing key.
//
//   sparkle-verify.swift --verify <appcast.xml>            (embedded feed signature)
//   sparkle-verify.swift --verify <file> <base64-signature>
//
// The key is SPARKLE_PUBLIC_ED_KEY (base64), else SUPublicEDKey from the app's
// Info.plist. The feed format matches Sparkle's SPUExtractAppcastContent: the
// signed bytes are everything before the last "<!-- sparkle-signatures:\n".
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func publicKeyBase64() -> String {
    if let key = ProcessInfo.processInfo.environment["SPARKLE_PUBLIC_ED_KEY"], !key.isEmpty {
        return key
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let plist = root.appendingPathComponent("App/APM44Bridge/Info.plist")
    guard let info = NSDictionary(contentsOf: plist), let key = info["SUPublicEDKey"] as? String else {
        fail("no SUPublicEDKey in \(plist.path) and SPARKLE_PUBLIC_ED_KEY is unset")
    }
    return key
}

/// Returns the signed content and the embedded signature of a signed feed.
func extractFeed(_ data: Data) -> (content: Data, signature: String) {
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    guard let prefixRange = data.range(of: prefix, options: .backwards) else {
        fail("appcast has no sparkle-signatures block (is it signed?)")
    }
    guard let suffixRange = data.range(of: Data("-->".utf8), in: prefixRange.upperBound..<data.endIndex),
          let block = String(data: data[prefixRange.upperBound..<suffixRange.lowerBound], encoding: .utf8) else {
        fail("appcast sparkle-signatures block is malformed")
    }
    let signature = block.split(separator: "\n")
        .first { $0.hasPrefix("edSignature:") }
        .map { $0.dropFirst("edSignature:".count).trimmingCharacters(in: .whitespaces) }
    guard let signature else { fail("appcast sparkle-signatures block has no edSignature") }
    return (data[data.startIndex..<prefixRange.lowerBound], signature)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.first == "--verify", args.count == 2 || args.count == 3 else {
    fail("usage: sparkle-verify.swift --verify <file> [<base64-signature>]")
}
guard let data = FileManager.default.contents(atPath: args[1]) else { fail("cannot read \(args[1])") }
let (content, signatureBase64) = args.count == 3 ? (data, args[2]) : extractFeed(data)

guard let keyData = Data(base64Encoded: publicKeyBase64()), keyData.count == 32,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("public Ed25519 key must be 32 bytes of base64")
}
guard let signature = Data(base64Encoded: signatureBase64), signature.count == 64 else {
    fail("signature must be 64 bytes of base64")
}
guard key.isValidSignature(signature, for: content) else {
    fail("failed to pass signing verification for \(args[1])")
}
