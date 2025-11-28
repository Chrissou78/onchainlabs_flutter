import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';
import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:bip32_plus/bip32_plus.dart' as bip32;
import 'package:hex/hex.dart';

import 'api.dart';
import 'models.dart';
import 'eip7702_execute.dart';

class PolygonWalletManager {
  static const String _mnemonicKey = 'wlltMnic';

  final PolygonWalletApi api;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  PolygonWalletManager({required this.api});

  static Future<PolygonWalletManager> create(
      PolygonWalletApi api) async {
    return PolygonWalletManager(api: api);
  }

  /// Create a new wallet and store mnemonic securely.
  ///
  /// No backend calls here.
  Future<PolygonWallet> createWallet() async {
    final mnemonic = bip39.generateMnemonic(strength: 128);
    final wallet = _walletFromMnemonic(mnemonic);

    await _storage.write(key: _mnemonicKey, value: mnemonic);
    return wallet;
  }

  /// Load stored wallet if possible, otherwise create a new one (local only).
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

    final backendAddr = await api.registerWallet(challenge, sig);

    if (backendAddr.toLowerCase() != wallet.address.toLowerCase()) {
      throw Exception('Backend address mismatch');
    }

    await _storage.write(key: _mnemonicKey, value: trimmed);
    return wallet;
  }

  /// Remove stored mnemonic from secure storage.
  Future<void> clearStoredMnemonic() async {
    await _storage.delete(key: _mnemonicKey);
  }

  /// Low-level: call backend /random directly.
  Future<String> fetchRandomMessage(String address) {
    return api.getRandomMessage(address);
  }

  /// Low-level: call backend /register directly.
  Future<String> authWithSignature(
      String message, String signature) {
    return api.registerWallet(message, signature);
  }

  /// High-level: full auth flow for a given wallet.
  Future<String> authenticateWallet(PolygonWallet wallet) async {
    final challenge = await api.getRandomMessage(wallet.address);
    final sig = await _signMessage(
      privateKeyHex: wallet.privateKeyHex,
      message: challenge,
    );
    final backendAddr = await api.registerWallet(challenge, sig);

    if (backendAddr.toLowerCase() != wallet.address.toLowerCase()) {
      throw Exception('Backend address mismatch');
    }

    return backendAddr;
  }

  /// High-level: auth flow using the stored mnemonic wallet.
  Future<String> authenticateStoredWallet() async {
    final saved = await _storage.read(key: _mnemonicKey);
    if (saved == null || saved.trim().isEmpty) {
      throw Exception('No stored mnemonic');
    }

    final wallet = _walletFromMnemonic(saved);
    return authenticateWallet(wallet);
  }

  // ---------- Gasless mint (EIP-7702) ----------

  /// Gasless mint using EIP-7702 execute().
  ///
  /// - adminMnemonic: admin / minter wallet mnemonic (already delegated)
  /// - destinationWallet: receiver (user wallet)
  /// - amount: HUMAN amount ("1000", "1.5", etc.), converted to 6 decimals
  /// - mintContractAddress: your MintToken contract address
  Future<Map<String, dynamic>> mintGaslessWithAdmin({
    required String adminMnemonic,
    required PolygonWallet destinationWallet,
    required String amount,
    required String mintContractAddress,
    bool waitForTx = false,
  }) async {
    // 1) Derive admin signer
    final seed = bip39.mnemonicToSeed(adminMnemonic);
    final root = bip32.BIP32.fromSeed(seed);
    const path = "m/44'/60'/0'/0/0";
    final child = root.derivePath(path);

    final privBytes = child.privateKey;
    if (privBytes == null) {
      throw Exception('Admin private key derivation failed');
    }

    final privHex = HEX.encode(privBytes);
    final adminSigner = EthPrivateKey.fromHex(privHex);

    // 2) Convert human amount to base units (6 decimals)
    final baseAmount = _toBaseUnits(amount, decimals: 6);

    // 3) Use EIP-7702 executor
    final executor = Eip7702Executor(api: api);

    return executor.executeMintGasless(
      adminSigner: adminSigner,
      destination: destinationWallet,
      amountBaseUnits: baseAmount,
      waitForTx: waitForTx,
      mintContractAddress: mintContractAddress,
    );
  }

  /// Check if the admin wallet (derived from mnemonic) is delegated.
  ///
  /// This does NOT perform the EIP-7702 authorize(). It only calls /status.
  /// If not delegated, this throws with an error.
  Future<void> checkAdminDelegation({
    required String adminMnemonic,
  }) async {
    final seed = bip39.mnemonicToSeed(adminMnemonic);
    final root = bip32.BIP32.fromSeed(seed);
    const path = "m/44'/60'/0'/0/0";
    final child = root.derivePath(path);

    final privBytes = child.privateKey;
    if (privBytes == null) {
      throw Exception('Admin private key derivation failed');
    }

    final privHex = HEX.encode(privBytes);
    final adminSigner = EthPrivateKey.fromHex(privHex);

    final executor = Eip7702Executor(api: api);
    await executor.ensureDelegated(adminSigner);
  }

  // ---------- Wallet derivation / signing helpers ----------

  /// Derive Polygon/EVM wallet from BIP39 mnemonic using BIP44 path.
  PolygonWallet _walletFromMnemonic(String mnemonic) {
    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);

    const path = "m/44'/60'/0'/0/0";
    final child = root.derivePath(path);

    final privBytes = child.privateKey;
    if (privBytes == null) {
      throw Exception('Private key derivation failed');
    }

    final privHex = HEX.encode(privBytes);
    final creds = EthPrivateKey.fromHex(privHex);

    // Former logic: use toString() and force 0x prefix if missing.
    final raw = creds.address.toString();
    final addr = raw.startsWith('0x') ? raw : '0x$raw';

    return PolygonWallet(
      address: addr,
      privateKeyHex: privHex,
      mnemonic: mnemonic,
    );
  }

  /// Sign message in Ethereum personal_sign format and return 0x-hex.
  Future<String> _signMessage({
    required String privateKeyHex,
    required String message,
  }) async {
    final creds = EthPrivateKey.fromHex(privateKeyHex);
    final payload = Uint8List.fromList(utf8.encode(message));

    final sigBytes = creds.signPersonalMessageToUint8List(payload);
    return '0x${HEX.encode(sigBytes)}';
  }

  /// Convert human amount (e.g. "1000" or "1.23") into base units string
  /// with [decimals] decimal places (e.g. 6 -> "1000000000" or "1230000").
  String _toBaseUnits(String humanAmount, {required int decimals}) {
    final input = humanAmount.trim();
    if (input.isEmpty) {
      throw Exception('Amount cannot be empty');
    }

    if (input.split('.').length > 2) {
      throw Exception('Invalid amount format');
    }

    String whole;
    String frac;

    if (input.contains('.')) {
      final parts = input.split('.');
      whole = parts[0];
      frac = parts[1];
    } else {
      whole = input;
      frac = '';
    }

    if (whole.startsWith('+')) {
      whole = whole.substring(1);
    }

    if (whole.startsWith('-')) {
      throw Exception('Amount cannot be negative');
    }

    final wholeDigits = whole.isEmpty ? '0' : whole;
    if (!RegExp(r'^[0-9]+$').hasMatch(wholeDigits)) {
      throw Exception('Invalid whole part in amount');
    }

    if (frac.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(frac)) {
      throw Exception('Invalid fractional part in amount');
    }

    if (frac.length > decimals) {
      throw Exception(
        'Too many decimal places. Max is $decimals for this token.',
      );
    }

    final paddedFrac = frac.padRight(decimals, '0');

    final combined = wholeDigits + paddedFrac;

    final noLeadingZeros =
        combined.replaceFirst(RegExp(r'^0+'), '');
    return noLeadingZeros.isEmpty ? '0' : noLeadingZeros;
  }
}
