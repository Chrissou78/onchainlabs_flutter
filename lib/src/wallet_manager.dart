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

  Future<PolygonWallet> createWallet() async {
    final mnemonic = bip39.generateMnemonic(strength: 128);
    final wallet = _walletFromMnemonic(mnemonic);

    final challenge = await api.getRandomMessage(wallet.address);
    final sig = await _signMessage(
      privateKeyHex: wallet.privateKeyHex,
      message: challenge,
    );

    final backendAddr = await api.registerWallet(challenge, sig);

    if (backendAddr.toLowerCase() != wallet.address.toLowerCase()) {
      throw Exception("Backend address mismatch");
    }

    await _storage.write(key: _mnemonicKey, value: mnemonic);
    return wallet;
  }

  Future<PolygonWallet> initWallet() async {
    final saved = await _storage.read(key: _mnemonicKey);

    if (saved != null && saved.trim().isNotEmpty) {
      try {
        return _walletFromMnemonic(saved);
      } catch (_) {
        throw Exception(
            "Could not initialize wallet from stored mnemonic");
      }
    }

    return createWallet();
  }

  Future<PolygonWallet> restoreWallet(String mnemonic) async {
    final trimmed = mnemonic.trim();

    if (!bip39.validateMnemonic(trimmed)) {
      throw Exception("Invalid mnemonic");
    }

    final wallet = _walletFromMnemonic(trimmed);

    final challenge = await api.getRandomMessage(wallet.address);
    final sig = await _signMessage(
      privateKeyHex: wallet.privateKeyHex,
      message: challenge,
    );

    final backendAddr = await api.registerWallet(challenge, sig);

    if (backendAddr.toLowerCase() != wallet.address.toLowerCase()) {
      throw Exception("Backend address mismatch");
    }

    await _storage.write(key: _mnemonicKey, value: trimmed);
    return wallet;
  }

  Future<void> clearStoredMnemonic() async {
    await _storage.delete(key: _mnemonicKey);
  }

  PolygonWallet _walletFromMnemonic(String mnemonic) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);

    const path = "m/44'/60'/0'/0/0";
    final child = root.derivePath(path);

    final privBytes = child.privateKey;
    if (privBytes == null) {
      throw Exception("Private key derivation failed");
    }

    final privHex = HEX.encode(privBytes);
    final creds = EthPrivateKey.fromHex(privHex);

    final rawAddr = creds.address.toString();
    final addr = rawAddr.startsWith("0x") ? rawAddr : "0x$rawAddr";

    return PolygonWallet(
      address: addr,
      privateKeyHex: privHex,
      mnemonic: mnemonic,
    );
  }

  Future<String> _signMessage({
    required String privateKeyHex,
    required String message,
  }) async {
    final creds = EthPrivateKey.fromHex(privateKeyHex);
    final payload = Uint8List.fromList(utf8.encode(message));

    final sig = creds.signPersonalMessageToUint8List(payload);
    return "0x${HEX.encode(sig)}";
  }
}
