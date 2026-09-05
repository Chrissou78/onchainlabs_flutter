// lib/src/wallet_manager.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'api_onchainlabs.dart';
import 'eip7702_executor.dart';

/// Thrown when contract addresses cannot be established during
/// [WalletManager.initialize].
///
/// The SDK does not substitute defaults for these addresses: the delegate
/// address determines which contract the wallet delegates its account to, so
/// operating on a guessed value is worse than not operating at all.
class ContractDiscoveryException implements Exception {
  final String message;
  const ContractDiscoveryException(this.message);

  @override
  String toString() => 'ContractDiscoveryException: $message';
}

/// Manages wallet operations with secure storage
class WalletManager {
  final FlutterSecureStorage _storage;
  final OnchainLabsApi _api;
  Eip7702Executor? _executor;
  
  String? _delegateAddress;
  String? _orocashAddress;

  WalletManager._({
    required FlutterSecureStorage storage,
    required OnchainLabsApi api,
  })  : _storage = storage,
        _api = api;

  /// Create a new WalletManager instance
  static Future<WalletManager> create({
    required String baseUrl,
    required String rpcUrl,
    int chainId = 80002,
  }) async {
    final storage = const FlutterSecureStorage();
    final api = OnchainLabsApiImpl(baseUrl: baseUrl);
    
    final manager = WalletManager._(storage: storage, api: api);
    await manager.initialize(rpcUrl: rpcUrl, chainId: chainId);
    
    return manager;
  }

  /// Initialize the wallet manager
  Future<void> initialize({
    required String rpcUrl,
    int chainId = 80002,
  }) async {
    // The delegate address returned here becomes the contract this wallet
    // signs an EIP-7702 authorisation to — the highest-consequence signature
    // the SDK produces. A previous version fell back to hard-coded addresses
    // when this call failed, which turned an unreachable endpoint into a
    // silent redirection onto a different contract pair. Fail closed instead:
    // the caller must be able to tell "not configured" from "configured".
    final Map<String, dynamic> contractsResult;
    try {
      contractsResult = await _api.getContracts();
    } catch (e) {
      throw ContractDiscoveryException(
        'Could not reach the contract configuration endpoint at '
        '${_api.baseUrl}/contracts: $e',
      );
    }

    if (contractsResult['success'] != true) {
      throw ContractDiscoveryException(
        'Contract configuration request was rejected: '
        '${contractsResult['message'] ?? 'no reason given'}',
      );
    }

    _delegateAddress = contractsResult['delegation'] ??
        contractsResult['delegator'] ??
        contractsResult['delegateAddress'];
    _orocashAddress = contractsResult['gold'] ?? contractsResult['orocash'];

    if (_delegateAddress == null || _delegateAddress!.isEmpty) {
      throw ContractDiscoveryException(
        'Contract configuration contained no delegate address.',
      );
    }

    final config = Eip7702Config(
      rpcUrl: rpcUrl,
      delegateAddress: _delegateAddress!,
      chainId: chainId,
    );
    
    _executor = Eip7702Executor(config: config, api: _api);
    // Note: Executor decimals will be initialized when wallet is loaded with privateKeyBytes
    // by calling executor.initialize(privateKeyBytes) from home_page.dart
    
  }

  /// Get the executor
  Eip7702Executor get executor {
    if (_executor == null) {
      throw StateError('WalletManager not initialized. Call initialize() first.');
    }
    return _executor!;
  }

  /// Get delegate address
  String? get delegateAddress => _delegateAddress;

  /// Get OroCash address
  String? get orocashAddress => _orocashAddress;

  /// Save wallet address
  Future<void> saveAddress(String address) async {
    await _storage.write(key: 'wallet_address', value: address);
  }

  /// Get saved wallet address
  Future<String?> getAddress() async {
    return await _storage.read(key: 'wallet_address');
  }

  /// Save private key
  Future<void> savePrivateKey(Uint8List privateKey) async {
    final hex = privateKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: 'private_key', value: hex);
  }

  /// Get private key
  Future<Uint8List?> getPrivateKey() async {
    final hex = await _storage.read(key: 'private_key');
    if (hex == null) return null;
    
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Overwrite [bytes] with zeros.
  ///
  /// Only meaningful for a buffer you own and are finished with. It cannot
  /// reach copies already made elsewhere, and it cannot touch Dart strings at
  /// all — those are immutable and may persist in the heap until the
  /// collector reclaims them, which is why key material should be passed and
  /// held as bytes rather than hex.
  static void zeroise(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }

  /// Run [action] with the private key, then zero the buffer.
  ///
  /// Preferred over [getPrivateKey] for one-off operations: the key is read
  /// inside the operation that needs it and overwritten as soon as that
  /// operation finishes, rather than living in the heap for the collector to
  /// reclaim whenever it chooses.
  ///
  /// ```dart
  /// final balance = await manager.withPrivateKey(
  ///   (key) => manager.executor.getOroCashBalanceFromWallet(key),
  /// );
  /// ```
  ///
  /// The buffer is zeroed even if [action] throws. Do not retain the
  /// [Uint8List] beyond the callback — it will be zeros afterwards, and any
  /// copy you make of it is outside this guarantee.
  ///
  /// This narrows exposure; it does not eliminate it. Anything the key is
  /// passed to may copy it, and the structural remedy is a hardware-backed
  /// key where the raw bytes never enter the process at all.
  Future<T> withPrivateKey<T>(FutureOr<T> Function(Uint8List key) action) async {
    final key = await getPrivateKey();
    if (key == null) {
      throw StateError('No private key is stored for this wallet.');
    }
    try {
      return await action(key);
    } finally {
      zeroise(key);
    }
  }

  /// Clear wallet data
  Future<void> clearWallet() async {
    await _storage.delete(key: 'wallet_address');
    await _storage.delete(key: 'private_key');
  }

  /// Delete wallet and clear cache
  Future<void> deleteWallet() async {
    executor.clearAuthCache();
    await clearWallet();
  }

  /// Check if wallet exists
  Future<bool> hasWallet() async {
    final address = await getAddress();
    return address != null && address.isNotEmpty;
  }

  /// Get OroCash balance as BigInt
  Future<BigInt> getOroCashBalance(Uint8List privateKeyBytes) async {
    return executor.getOroCashBalanceFromWallet(privateKeyBytes);
  }

  /// Get OroCash balance formatted (uses cached decimals from executor)
  Future<double> getOroCashBalanceFormatted(Uint8List privateKeyBytes) async {
    return executor.getOroCashBalanceFromWalletFormatted(privateKeyBytes);
  }

  /// Create mainnet wallet manager
  static Future<WalletManager> createMainnet(String baseUrl) {
    return WalletManager.create(
      baseUrl: baseUrl,
      rpcUrl: 'https://polygon-rpc.com',
      chainId: 137,
    );
  }

  /// Create Amoy testnet wallet manager
  static Future<WalletManager> createAmoy(String baseUrl) {
    return WalletManager.create(
      baseUrl: baseUrl,
      rpcUrl: 'https://rpc-amoy.polygon.technology',
      chainId: 80002,
    );
  }
}
