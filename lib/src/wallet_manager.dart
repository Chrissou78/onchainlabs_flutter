// lib/src/wallet_manager.dart

import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'api_onchainlabs.dart';
import 'eip7702_executor.dart';

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
    print('=== FETCHING CONTRACT ADDRESSES ===');
    print('API Base URL: ${_api.baseUrl}');
    
    try {
      final contractsResult = await _api.getContracts();
      print('Contracts result: $contractsResult');
      
      if (contractsResult['success'] == true) {
        _delegateAddress = contractsResult['delegation'] ?? 
                          contractsResult['delegator'] ?? 
                          contractsResult['delegateAddress'];
        _orocashAddress = contractsResult['gold'] ?? contractsResult['orocash'];
        print('Delegate Address: $_delegateAddress');
        print('OroCash Address: $_orocashAddress');
      } else {
        print('Failed to fetch contracts: ${contractsResult['message']}');
        _delegateAddress = '0xa7dE21f5Fc304F2d9E012B7FaAa786621173d61C';
        _orocashAddress = '0x367bCCB56c0661c47d0684777Ccf83C69c119A2B';
        print('Using default addresses');
      }
    } catch (e) {
      print('Error fetching contracts: $e');
      _delegateAddress = '0xa7dE21f5Fc304F2d9E012B7FaAa786621173d61C';
      _orocashAddress = '0x367bCCB56c0661c47d0684777Ccf83C69c119A2B';
      print('Using default addresses');
    }
    
    if (_delegateAddress == null || _delegateAddress!.isEmpty) {
      throw Exception('Delegate address is null or empty');
    }
    
    final config = Eip7702Config(
      rpcUrl: rpcUrl,
      delegateAddress: _delegateAddress!,
      chainId: chainId,
    );
    
    _executor = Eip7702Executor(config: config, api: _api);
    // Note: Executor decimals will be initialized when wallet is loaded with privateKeyBytes
    // by calling executor.initialize(privateKeyBytes) from home_page.dart
    
    print('=== WALLET MANAGER INITIALIZED ===');
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
