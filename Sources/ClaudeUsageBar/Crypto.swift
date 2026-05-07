import Foundation
import CommonCrypto

enum CryptoError: Error, CustomStringConvertible {
    case pbkdf2Failed(Int32)
    case decryptionFailed(CCCryptorStatus)
    case paddingInvalid
    case payloadTooShort

    var description: String {
        switch self {
        case .pbkdf2Failed(let s): return "PBKDF2 failed (\(s))"
        case .decryptionFailed(let s): return "AES decryption failed (\(s))"
        case .paddingInvalid: return "Invalid PKCS#7 padding"
        case .payloadTooShort: return "Decrypted payload shorter than the 32-byte host hash prefix"
        }
    }
}

enum Crypto {
    static func deriveKey(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { (derivedPtr: UnsafeMutableRawBufferPointer) -> Int32 in
            password.withUnsafeBytes { (pwPtr: UnsafeRawBufferPointer) -> Int32 in
                salt.withUnsafeBytes { (saltPtr: UnsafeRawBufferPointer) -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPBKDFAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.pbkdf2Failed(status) }
        return derived
    }

    static func aes128CBCDecrypt(ciphertext: Data, key: Data, iv: Data) throws -> Data {
        let outCapacity = ciphertext.count + kCCBlockSizeAES128
        var outBuffer = Data(count: outCapacity)
        var outLength = 0

        // We strip PKCS#7 manually below — pass CCOptions(0) and let the host-hash stripping decide.
        let status = outBuffer.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) -> CCCryptorStatus in
            ciphertext.withUnsafeBytes { (ctPtr: UnsafeRawBufferPointer) -> CCCryptorStatus in
                key.withUnsafeBytes { (keyPtr: UnsafeRawBufferPointer) -> CCCryptorStatus in
                    iv.withUnsafeBytes { (ivPtr: UnsafeRawBufferPointer) -> CCCryptorStatus in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(0),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            ctPtr.baseAddress, ciphertext.count,
                            outPtr.baseAddress, outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.decryptionFailed(status) }
        outBuffer.removeSubrange(outLength..<outBuffer.count)
        return outBuffer
    }

    static func stripPKCS7Padding(_ data: Data) throws -> Data {
        guard let last = data.last else { throw CryptoError.paddingInvalid }
        let pad = Int(last)
        guard pad >= 1, pad <= 16, data.count >= pad else { throw CryptoError.paddingInvalid }
        let tail = data.suffix(pad)
        guard tail.allSatisfy({ $0 == last }) else { throw CryptoError.paddingInvalid }
        return data.dropLast(pad)
    }
}
