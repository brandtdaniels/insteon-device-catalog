import Crypto

/// SHA-256 digests, written as the lowercase hexadecimal text a manifest holds.
public enum Checksum {
  /// The SHA-256 digest of `bytes` as 64 lowercase hexadecimal digits.
  public static func sha256Hex(of bytes: [UInt8]) -> String {
    SHA256.hash(data: bytes).map { byte in
      let digits = String(byte, radix: 16)
      return digits.count == 1 ? "0" + digits : digits
    }.joined()
  }
}
