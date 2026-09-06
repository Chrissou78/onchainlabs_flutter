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

  /// Keychain accessibility the SDK uses for its own key material.
  ///
  /// The plugin default is `unlocked` (`kSecAttrAccessibleWhenUnlocked`),
  /// which is eligible for encrypted iTunes and iCloud backups and migrates
  /// to a restored device. `first_unlock_this_device` stays on the device it
  /// was written on. Closes the iOS half of audit finding K-03.
  ///
  /// Safe on upgrade: reads do not filter on this attribute, so keys already
  /// stored remain readable. It applies to writes, and iOS does not permit
  /// changing it via update — so an existing key keeps the weaker attribute
  /// until it is written again.
  static const IOSOptions defaultIosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  /// Android storage options the SDK uses for its own key material.
  ///
  /// Deliberately the plugin default. The Android half of K-03 wants
  /// `encryptedSharedPreferences: true`, but that selects a different backing
  /// store, and the plugin requires the same setting on **every**
  /// `FlutterSecureStorage` in the process. A library cannot flip it
  /// unilaterally without risking mixed-usage errors and unreadable data in
  /// the host application, which keeps its own instances.
  ///
  /// Enable it from the app, passing the same options here and everywhere you
  /// construct storage yourself, and plan a migration for data already
  /// written:
  ///
  /// ```dart
  /// await WalletManager.createAmoy(
  ///   baseUrl,
  ///   androidOptions: const AndroidOptions(encryptedSharedPreferences: true),
  /// );
  /// ```
  static const AndroidOptions defaultAndroidOptions = AndroidOptions();

  /// Create a new WalletManager instance
  static Future<WalletManager> create({
    required String baseUrl,
    required String rpcUrl,
    int chainId = 80002,
    String? delegateAddress,
    String? tokenAddress,
    IOSOptions iosOptions = defaultIosOptions,
    AndroidOptions androidOptions = defaultAndroidOptions,
  }) async {
    final storage = FlutterSecureStorage(
      iOptions: iosOptions,
      aOptions: androidOptions,
    );
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
  static const _hexDigits = '0123456789abcdef';

  /// Hex digit to value, or -1.
  static int _hexValue(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30; // 0-9
    if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x57; // a-f
    if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x37; // A-F
    return -1;
  }

  /// Save private key
  ///
  /// Encodes through a byte buffer that is zeroed afterwards, rather than
  /// `map().join()`. The old form allocated one immutable two-character
  /// string per byte plus the joined result — 33 copies of key material for a
  /// 32-byte key, none of which can be overwritten, all of them resident
  /// until the collector chooses otherwise. One string still reaches storage
  /// because the platform API takes a string; the other 32 no longer exist.
  Future<void> savePrivateKey(Uint8List privateKey) async {
    final codes = Uint8List(privateKey.length * 2);
    try {
      for (var i = 0; i < privateKey.length; i++) {
        final b = privateKey[i];
        codes[i * 2] = _hexDigits.codeUnitAt(b >> 4);
        codes[i * 2 + 1] = _hexDigits.codeUnitAt(b & 0x0f);
      }
      await _storage.write(key: 'private_key', value: String.fromCharCodes(codes));
    } finally {
      zeroise(codes);
    }
  }

  /// Get private key
  ///
  /// Decodes by code unit into a pre-sized buffer. The old form called
  /// `substring` per byte, so reading a 32-byte key left 32 immutable
  /// two-character strings of key material in the heap, then built a growable
  /// list that reallocated several times before being copied again.
  Future<Uint8List?> getPrivateKey() async {
    final hex = await _storage.read(key: 'private_key');
    if (hex == null) return null;
    if (hex.isEmpty || hex.length.isOdd) {
      throw FormatException(
        'Stored private key is not valid hex (${hex.length} characters).',
      );
    }

    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final hi = _hexValue(hex.codeUnitAt(i * 2));
      final lo = _hexValue(hex.codeUnitAt(i * 2 + 1));
      if (hi < 0 || lo < 0) {
        zeroise(out);
        throw const FormatException(
          'Stored private key contains a non-hex character.',
        );
      }
      out[i] = (hi << 4) | lo;
    }
    return out;
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
    IOSOptions iosOptions = defaultIosOptions,
    AndroidOptions androidOptions = defaultAndroidOptions,
  }) {
    return WalletManager.create(
      baseUrl: baseUrl,
      rpcUrl: 'https://polygon-rpc.com',
      chainId: 137,
      delegateAddress: delegateAddress,
      tokenAddress: tokenAddress,
      iosOptions: iosOptions,
      androidOptions: androidOptions,
    );
  }

  /// Create Amoy testnet wallet manager
  static Future<WalletManager> createAmoy(
    String baseUrl, {
    String? delegateAddress,
    String? tokenAddress,
    IOSOptions iosOptions = defaultIosOptions,
    AndroidOptions androidOptions = defaultAndroidOptions,
  }) {
    return WalletManager.create(
      baseUrl: baseUrl,
      rpcUrl: 'https://rpc-amoy.polygon.technology',
      chainId: 80002,
      delegateAddress: delegateAddress,
      tokenAddress: tokenAddress,
      iosOptions: iosOptions,
      androidOptions: androidOptions,
    );
  }
}
