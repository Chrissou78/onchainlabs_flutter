import 'dart:convert';
import 'dart:typed_data';
import 'package:web3dart/web3dart.dart';
import 'package:convert/convert.dart';

/// Helper class for building delegated transaction signatures
/// that match Solidity's executeDelegated pattern.
class DelegatedSigningHelper {
  /// Builds the struct hash that matches Solidity:
  /// keccak256(abi.encode(address(this), signer, nonce, deadline, keccak256(data)))
  static Uint8List buildStructHash({
    required String contractAddress,
    required String signerAddress,
    required BigInt nonce,
    required BigInt deadline,
    required Uint8List data,
  }) {
    // First, hash the data
    final dataHash = keccak256(data);

    // Normalize addresses to lowercase for consistent encoding
    final normalizedContract = contractAddress.toLowerCase();
    final normalizedSigner = signerAddress.toLowerCase();

    // Now encode all parameters together
    // ABI encoding: address, address, uint256, uint256, bytes32
    final encoded = _abiEncode([
      _addressToBytes32(normalizedContract),
      _addressToBytes32(normalizedSigner),
      _uint256ToBytes32(nonce),
      _uint256ToBytes32(deadline),
      dataHash,
    ]);

    // Return the keccak256 of the entire encoding
    return keccak256(encoded);
  }

  /// Signs the struct hash WITHOUT personal_sign prefix (raw signature)
  /// For delegated transactions that will be verified on-chain
  static Uint8List signStructHashRaw({
    required Uint8List structHash,
    required EthPrivateKey credentials,
  }) {
    // Sign the struct hash directly without personal_sign prefix
    // The contract will verify this against the recovered address
    final signature = credentials.signToEcSignature(structHash);
    
    // Convert signature to bytes (r + s + v format, 65 bytes total)
    final r = _uint256ToBytes32(signature.r);
    final s = _uint256ToBytes32(signature.s);
    
    // Ensure v is in the correct format (27 or 28)
    int v = signature.v;
    if (v < 27) {
      v += 27;
    }
    final vByte = Uint8List.fromList([v]);
    
    return Uint8List.fromList([...r, ...s, ...vByte]);
  }

  /// Signs the struct hash with Ethereum's personal_sign prefix
  /// This matches ethers.js signMessage(getBytes(structHash))
  static Future<Uint8List> signStructHash({
    required Uint8List structHash,
    required EthPrivateKey credentials,
  }) async {
    // Use the delegation-specific signing method
    return signStructHashForDelegation(
      structHash: structHash,
      credentials: credentials,
    );
  }

  /// Signs a message using Ethereum's personal_sign (for API authentication)
  /// The message is treated as UTF-8 text (NOT converted from hex to bytes)
  static Future<Uint8List> signPersonalMessage({
    required EthPrivateKey credentials,
    required String message,
  }) async {
    // For authentication, always treat the message as UTF-8 text
    // Even if it's a hex string like "0x123...", we sign the text itself
    final payload = Uint8List.fromList(utf8.encode(message));
    final sig = await credentials.signPersonalMessageToUint8List(payload);
    return sig;
  }

  /// Signs the struct hash for delegated transactions
  /// The struct hash (hex string) is converted to bytes before signing
  /// This matches: await signerWallet.signMessage(getBytes(structHash))
  static Future<Uint8List> signStructHashForDelegation({
    required Uint8List structHash,
    required EthPrivateKey credentials,
  }) async {
    // Sign the struct hash bytes directly (like ethers getBytes + signMessage)
    final sig = await credentials.signPersonalMessageToUint8List(structHash);
    return sig;
  }

  /// Helper: Convert Ethereum address to bytes32 (left-padded with zeros)
  static Uint8List _addressToBytes32(String address) {
    // Remove 0x prefix if present
    String addr = address.toLowerCase();
    if (addr.startsWith('0x')) {
      addr = addr.substring(2);
    }

    // Address is 20 bytes, pad to 32 bytes (left-pad with zeros)
    final addressBytes = hex.decode(addr);
    final padded = Uint8List(32);
    padded.setRange(32 - addressBytes.length, 32, addressBytes);
    return padded;
  }

  /// Helper: Convert uint256 to bytes32 (big-endian, left-padded)
  static Uint8List _uint256ToBytes32(BigInt value) {
    final bytes = _encodeBigInt(value);
    if (bytes.length > 32) {
      throw ArgumentError('Value too large for uint256');
    }

    // Pad to 32 bytes (left-pad with zeros)
    final padded = Uint8List(32);
    padded.setRange(32 - bytes.length, 32, bytes);
    return padded;
  }

  /// Encode BigInt to bytes (big-endian)
  static Uint8List _encodeBigInt(BigInt number) {
    if (number == BigInt.zero) {
      return Uint8List.fromList([0]);
    }

    final bytes = <int>[];
    var temp = number;
    while (temp > BigInt.zero) {
      bytes.insert(0, (temp & BigInt.from(0xff)).toInt());
      temp = temp >> 8;
    }
    return Uint8List.fromList(bytes);
  }

  /// ABI encode multiple bytes32 values by concatenating them
  static Uint8List _abiEncode(List<Uint8List> values) {
    final result = <int>[];
    for (final value in values) {
      if (value.length != 32) {
        throw ArgumentError('All values must be 32 bytes for this encoding');
      }
      result.addAll(value);
    }
    return Uint8List.fromList(result);
  }

  /// Convert signature bytes to hex string with 0x prefix
  static String signatureToHex(Uint8List signature) {
    return '0x${hex.encode(signature)}';
  }

  /// Convert bytes to hex string with 0x prefix
  static String bytesToHex(Uint8List bytes) {
    return '0x${hex.encode(bytes)}';
  }

  /// Parse hex string to bytes (removes 0x prefix if present)
  static Uint8List hexToBytes(String hexString) {
    String cleaned = hexString;
    if (cleaned.startsWith('0x')) {
      cleaned = cleaned.substring(2);
    }
    return Uint8List.fromList(hex.decode(cleaned));
  }
}