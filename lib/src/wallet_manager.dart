import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';
import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:bip32_plus/bip32_plus.dart' as bip32;
import 'package:hex/hex.dart';

import 'api.dart';
import 'models.dart';

class PolygonWalletManager {
  static const String _mnemonicKey = 'wlltMnic';

  final PolygonWalletApi api;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  PolygonWalletManager({required this.api});

  static Future<PolygonWalletManager> create(PolygonWalletApi api) async {
    return PolygonWalletManager(api: api);
  }

  /// Create a new wallet, register it with backend, and store mnemonic securely.
  Future<PolygonWallet> createWallet() async {
    final mnemonic = bip39.generateMnemonic(strength: 128);
    final wallet = _walletFromMnemonic(mnemonic);

    final challenge = await api.getRandomMessage(wallet.address);
    final sig = await _signMessage(
      privateKeyHex: wallet.privateKeyHex,
      message: challenge,
    );

    final addr = await api.registerWallet(challenge, sig);

    if (addr.toLowerCase() != wallet.address.toLowerCase()) {
      throw Exception('Backend address mismatch');
    }

    await _storage.write(key: _mnemonicKey, value: wallet.mnemonic);
    return wallet;
  }

  /// Load stored wallet if possible, otherwise create a new one.
  Future<PolygonWallet> initWallet() async {
    final saved = await _storage.read(key: _mnemonicKey);

    if (saved != null && saved.trim().isNotEmpty) {
      try {
        return _walletFromMnemonic(saved);
      } catch (_) {
        throw Exception(
          'Failed to initialize wallet from stored mnemonic. '
          'Create a new wallet or restore from a valid mnemonic.',
        );
      }
    }

    return createWallet();
  }

  /// Restore from user-provided mnemonic, register, store it securely.
  Future<PolygonWallet> restoreWallet(String mnemonic) async {
    final trimmed = mnemonic.trim();

    if (!bip39.validateMnemonic(trimmed)) {
      throw Exception('Invalid mnemonic');
    }

    final wallet = _walletFromMnemonic(trimmed);

    final challenge = await api.getRandomMessage(wallet.address);
    final sig = await _signMessage(
      privateKeyHex: wallet.privateKeyHex,
      message: challenge,
    );

    final addr = await api.registerWallet(challenge, sig);

    if (addr.toLowerCase() != wallet.address.toLowerCase()) {
      throw Exception('Backend address mismatch');
    }

    await _storage.write(key: _mnemonicKey, value: wallet.mnemonic);
    return wallet;
  }

  /// Remove stored mnemonic from secure storage.
  Future<void> clearStoredMnemonic() async {
    await _storage.delete(key: _mnemonicKey);
  }

  /// Derive Polygon/EVM wallet from BIP39 mnemonic using BIP44 path.
  PolygonWallet _walletFromMnemonic(String mnemonic) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);

    // Standard derivation path for Ethereum / Polygon
    const path = "m/44'/60'/0'/0/0";
    final child = root.derivePath(path);

    final privBytes = child.privateKey;
    if (privBytes == null) {
      throw Exception('Failed to derive private key');
    }

    final privHex = HEX.encode(privBytes);
    final creds = EthPrivateKey.fromHex(privHex);

    // Use toString() to avoid depending on removed getters like `.hex`
    final addrHex = creds.address.toString();

    return PolygonWallet(
      address: addrHex,
      privateKeyHex: privHex,
      mnemonic: mnemonic,
    );
  }

  /// Sign message in Ethereum personal_sign format and return hex string.
  Future<String> _signMessage({
    required String privateKeyHex,
    required String message,
  }) async {
    final creds = EthPrivateKey.fromHex(privateKeyHex);
    final payload = Uint8List.fromList(utf8.encode(message));

    // web3dart >=2.7.x exposes this helper
    final sigBytes = creds.signPersonalMessageToUint8List(payload);

    return '0x${HEX.encode(sigBytes)}';
  }
}
