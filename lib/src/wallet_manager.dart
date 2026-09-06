// lib/src/wallet_manager.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'api_onchainlabs.dart';
import 'eip7702_executor.dart';

/// The contract pair a wallet operates against on one chain.
class OnchainLabsContracts {
  /// The contract an EIP-7702 authorisation delegates the account to.
  final String delegate;

  /// The OROCASH token contract.
  final String token;

  const OnchainLabsContracts({required this.delegate, required this.token});
}

/// Contract addresses per chain, as release constants.
///
/// These are deliberately not fetched at runtime. The delegate address
/// determines which contract a wallet delegates its account to — the
/// highest-consequence signature this SDK produces — and `/contracts` is
/// unauthenticated and unpinned, so whoever answers that request would choose
/// it. The addresses do not change between deployments, so there is nothing to
/// gain by asking for them and a great deal to lose.
///
/// Verified on-chain on 6 September 2026 via eth_getCode: each address carries
/// contract code on its own chain and none on the other.
const Map<int, OnchainLabsContracts> kOnchainLabsContracts = {
  // Polygon mainnet
  137: OnchainLabsContracts(
    delegate: '0x11a2C6C6368376Dd97d2D8Ad45eff904E4186BDD',
    token: '0x4CD6FFD022F3d777425F1f3BBf4DeD66d3eD1Fad',
  ),
  // Polygon Amoy testnet
  80002: OnchainLabsContracts(
    delegate: '0xAC5d44B5d38e8E3541D79B005AcC2E8965A2b291',
    token: '0xcc7fA40292D7CaD12C2033d613ce483C1A89a8A2',
  ),
};

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
    String? delegateAddress,
    String? tokenAddress,
  }) async {
    final storage = const FlutterSecureStorage();
    final api = OnchainLabsApiImpl(baseUrl: baseUrl);

    final manager = WalletManager._(storage: storage, api: api);
    await manager.initialize(
      rpcUrl: rpcUrl,
      chainId: chainId,
      delegateAddress: delegateAddress,
      tokenAddress: tokenAddress,
    );

    return manager;
  }

  /// Initialise against the release constants for [chainId].
  ///
  /// No network call is made. [delegateAddress] and [tokenAddress] override
  /// the constants, which is how you reach a chain this release does not know
  /// about or a private deployment. Supplying one requires the other.
  Future<void> initialize({
    required String rpcUrl,
    int chainId = 80002,
    String? delegateAddress,
    String? tokenAddress,
  }) async {
    if ((delegateAddress == null) != (tokenAddress == null)) {
      throw ArgumentError(
        'delegateAddress and tokenAddress must be supplied together.',
      );
    }

    if (delegateAddress != null) {
      _delegateAddress = delegateAddress;
      _orocashAddress = tokenAddress;
    } else {
      final known = kOnchainLabsContracts[chainId];
      if (known == null) {
        throw ContractDiscoveryException(
          'No contract addresses are compiled in for chain $chainId. '
          'Known chains: ${kOnchainLabsContracts.keys.join(', ')}. '
          'Pass delegateAddress and tokenAddress explicitly to use another.',
        );
      }
      _delegateAddress = known.delegate;
      _orocashAddress = known.token;
    }

    // Validate whatever we ended up with. An address that is not 20 bytes of
    // hex would otherwise be discovered deep inside signing.
    Eip7702Executor.requireAddressHex(_delegateAddress!, 'delegateAddress');
    Eip7702Executor.requireAddressHex(_orocashAddress!, 'tokenAddress');

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
  static Future<WalletManager> createMainnet(
    String baseUrl, {
    String? delegateAddress,
    String? tokenAddress,
  }) {
    return WalletManager.create(
      baseUrl: baseUrl,
      rpcUrl: 'https://polygon-rpc.com',
      chainId: 137,
      delegateAddress: delegateAddress,
      tokenAddress: tokenAddress,
    );
  }

  /// Create Amoy testnet wallet manager
  static Future<WalletManager> createAmoy(
    String baseUrl, {
    String? delegateAddress,
    String? tokenAddress,
  }) {
    return WalletManager.create(
      baseUrl: baseUrl,
      rpcUrl: 'https://rpc-amoy.polygon.technology',
      chainId: 80002,
      delegateAddress: delegateAddress,
      tokenAddress: tokenAddress,
    );
  }
}
