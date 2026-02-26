// lib/src/eip7702_executor.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/keccak.dart';
import 'package:web3dart/web3dart.dart';
import 'api.dart';

/// Keccak256 hash helper
Uint8List _keccak256(Uint8List data) {
  final digest = KeccakDigest(256);
  return digest.process(data);
}

/// Convert hex string to bytes
Uint8List _hexToBytes(String hex) {
  final h = hex.startsWith('0x') ? hex.substring(2) : hex;
  if (h.isEmpty) return Uint8List(0);
  final result = Uint8List(h.length ~/ 2);
  for (var i = 0; i < h.length; i += 2) {
    result[i ~/ 2] = int.parse(h.substring(i, i + 2), radix: 16);
  }
  return result;
}

/// Convert bytes to hex string
String _bytesToHex(Uint8List bytes, {bool include0x = true}) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return include0x ? '0x$hex' : hex;
}

/// Convert address to checksum format
String _toChecksumAddress(String address) {
  final addr = address.toLowerCase().replaceAll('0x', '');
  final hash = keccak256(Uint8List.fromList(addr.codeUnits));
  
  final checksummed = StringBuffer('0x');
  for (int i = 0; i < addr.length; i++) {
    if (int.parse(hash[i ~/ 2].toRadixString(16).padLeft(2, '0')[i % 2], radix: 16) >= 8) {
      checksummed.write(addr[i].toUpperCase());
    } else {
      checksummed.write(addr[i]);
    }
  }
  return checksummed.toString();
}

class MembershipInfo {
  final bool isMember;
  final BigInt tokenId;
  final DateTime mintedAt;
  final String tokenURI;

  const MembershipInfo({
    required this.isMember,
    required this.tokenId,
    required this.mintedAt,
    required this.tokenURI,
  });

  factory MembershipInfo.empty() {
    return MembershipInfo(
      isMember: false,
      tokenId: BigInt.zero,
      mintedAt: DateTime.fromMillisecondsSinceEpoch(0),
      tokenURI: '',
    );
  }

  /// Check if membership is valid (exists)
  bool get isValid => isMember && tokenId > BigInt.zero;

  /// Format minted date
  String get formattedMintedAt {
    if (!isMember) return '';
    return '${mintedAt.year}-${mintedAt.month.toString().padLeft(2, '0')}-${mintedAt.day.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'MembershipInfo(isMember: $isMember, tokenId: $tokenId, mintedAt: $mintedAt, tokenURI: $tokenURI)';
  }
}

/// EIP-7702 configuration
class Eip7702Config {
  final String rpcUrl;
  final String delegateAddress;
  final String? tokenContractAddress;
  final int chainId;

  const Eip7702Config({
    required this.rpcUrl,
    required this.delegateAddress,
    this.tokenContractAddress,
    this.chainId = 80002,
  });
}

/// Result of an EIP-7702 operation
class Eip7702Result {
  final bool success;
  final String? txHash;
  final String? transactionId;
  final String? error;
  final Map<String, dynamic>? data;

  const Eip7702Result._({
    required this.success,
    this.txHash,
    this.transactionId,
    this.error,
    this.data,
  });

  factory Eip7702Result.success({
    String? txHash,
    String? transactionId,
    Map<String, dynamic>? data,
  }) {
    return Eip7702Result._(
      success: true,
      txHash: txHash,
      transactionId: transactionId,
      data: data,
    );
  }

  factory Eip7702Result.failure(String error) {
    return Eip7702Result._(success: false, error: error);
  }
}

/// Batch call structure
class BatchCall {
  final String to;
  final String data;
  final BigInt? value;
  
  BatchCall({required this.to, required this.data, this.value});
  
  Map<String, dynamic> toJson() => {
    'to': to,
    'value': (value ?? BigInt.zero).toString(),
    'data': data,
  };
}

/// Delegation status
class DelegationStatus {
  final bool isDelegated;
  final String? delegateAddress;

  const DelegationStatus({
    required this.isDelegated,
    this.delegateAddress,
  });
}

/// Gold price data
class GoldPrice {
  final double pricePerMg;
  final DateTime fetchedAt;
  
  const GoldPrice({
    required this.pricePerMg,
    required this.fetchedAt,
  });
  
  /// Price per gram (1000 mg)
  double get pricePerGram => pricePerMg * 1000;
  
  /// Price per troy ounce (31.1035 grams)
  double get pricePerOunce => pricePerGram * 31.1035;
  
  /// Format price per mg
  String get formattedPricePerMg => '\$${pricePerMg.toStringAsFixed(6)}';
  
  /// Format price per gram
  String get formattedPricePerGram => '\$${pricePerGram.toStringAsFixed(2)}';
  
  /// Format price per ounce
  String get formattedPricePerOunce => '\$${pricePerOunce.toStringAsFixed(2)}';
}

/// Result of gold price fetch
class GoldPriceResult {
  final bool success;
  final GoldPrice? price;
  final String? error;
  
  const GoldPriceResult._({
    required this.success,
    this.price,
    this.error,
  });
  
  factory GoldPriceResult.success(GoldPrice price) {
    return GoldPriceResult._(success: true, price: price);
  }
  
  factory GoldPriceResult.failure(String error) {
    return GoldPriceResult._(success: false, error: error);
  }
}

/// EIP-7702 Executor for gasless transactions
class Eip7702Executor {
  final Eip7702Config config;
  final OnchainLabsApi _api;
  
  // Cache for auth headers (valid for 4 hours)
  Map<String, String>? _cachedAuthHeaders;
  String? _cachedAddress;
  DateTime? _cacheExpiry;
  static const _cacheDuration = Duration(hours: 4);
  
  // Cached token info
  int _tokenDecimals = 6;  // Default, will be updated on init
  BigInt _decimalMultiplier = BigInt.from(1000000);  // 10^6 default
  bool _isInitialized = false;
  
  // Cached gold price
  GoldPrice? _cachedGoldPrice;
  DateTime? _goldPriceCacheExpiry;
  static const _goldPriceCacheDuration = Duration(minutes: 5);

  Eip7702Executor({
    required this.config,
    required OnchainLabsApi api,
  }) : _api = api;

  /// Initialize the executor and fetch token decimals
  Future<void> initialize(Uint8List privateKeyBytes) async {
    print('Eip7702Executor initializing with chainId: ${config.chainId}');
    
    try {
      // Fetch and cache token decimals
      _tokenDecimals = await _fetchTokenDecimals(privateKeyBytes);
      _decimalMultiplier = BigInt.from(10).pow(_tokenDecimals);
      _isInitialized = true;
      
      print('Token decimals cached: $_tokenDecimals');
      print('Decimal multiplier: $_decimalMultiplier');
    } catch (e) {
      print('Warning: Failed to fetch token decimals, using default (6): $e');
      _tokenDecimals = 6;
      _decimalMultiplier = BigInt.from(1000000);
      _isInitialized = true;
    }
  }

  /// Get cached token decimals
  int get tokenDecimals => _tokenDecimals;
  
  /// Get cached decimal multiplier
  BigInt get decimalMultiplier => _decimalMultiplier;
  
  /// Check if executor is initialized
  bool get isInitialized => _isInitialized;

  /// Convert human-readable amount to raw amount (with decimals)
  BigInt toRawAmount(double humanAmount) {
    return BigInt.from((humanAmount * _decimalMultiplier.toDouble()).round());
  }

  /// Convert raw amount to human-readable amount
  double toHumanAmount(BigInt rawAmount) {
    return rawAmount / _decimalMultiplier;
  }

  /// Format raw amount as string with proper decimal places
  String formatAmount(BigInt rawAmount, {int? decimalPlaces}) {
    final divisor = _decimalMultiplier;
    final whole = rawAmount ~/ divisor;
    final remainder = rawAmount % divisor;
    
    if (remainder == BigInt.zero) {
      return whole.toString();
    }
    
    final remainderStr = remainder.toString().padLeft(_tokenDecimals, '0');
    final trimmed = decimalPlaces != null 
        ? remainderStr.substring(0, decimalPlaces.clamp(0, _tokenDecimals))
        : remainderStr.replaceAll(RegExp(r'0+$'), '');
    
    if (trimmed.isEmpty) {
      return whole.toString();
    }
    return '$whole.$trimmed';
  }

  /// Fetch token decimals from contract
  Future<int> _fetchTokenDecimals(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('decimals', headers);
    if (result['success'] == true) {
      return int.tryParse(result['result']?.toString() ?? '6') ?? 6;
    }
    return 6;
  }

  /// Get the API instance
  OnchainLabsApi get api => _api;

  /// Get address from private key
  String getAddressFromPrivateKey(Uint8List privateKeyBytes) {
    final credentials = EthPrivateKey(privateKeyBytes);
    final address = credentials.address;
    
    print('Address type: ${address.runtimeType}');
    print('Address toString: ${address.toString()}');
    
    final addressStr = address.toString();
    final withPrefix = addressStr.startsWith('0x') ? addressStr : '0x$addressStr';
    return _toChecksumAddress(withPrefix);
  }

  /// Sign a message with private key (for API auth - personal_sign)
  String signMessage(Uint8List privateKeyBytes, String message) {
    final credentials = EthPrivateKey(privateKeyBytes);
    final messageBytes = Uint8List.fromList(utf8.encode(message));
    
    print('=== SIGN DEBUG ===');
    print('Message: $message');
    print('Message bytes length: ${messageBytes.length}');
    
    final signature = credentials.signPersonalMessageToUint8List(messageBytes);
    
    print('Signature length: ${signature.length}');
    
    final signatureHex = '0x${_bytesToHex(signature, include0x: false)}';
    print('Signature: $signatureHex');
    
    return signatureHex;
  }

  /// Create authentication headers
  Future<Map<String, String>> createAuthHeaders(Uint8List privateKeyBytes) async {
    final address = getAddressFromPrivateKey(privateKeyBytes);
    
    // Check if we have valid cached headers for this address
    if (_cachedAuthHeaders != null &&
        _cachedAddress == address &&
        _cacheExpiry != null &&
        DateTime.now().isBefore(_cacheExpiry!)) {
      print('=== USING CACHED AUTH HEADERS ===');
      return _cachedAuthHeaders!;
    }
    
    print('=== CREATING NEW AUTH HEADERS ===');
    print('Address: $address');
    
    // Get random message
    final randomResult = await _api.getRandomMessage(address);
    if (randomResult['success'] != true) {
      throw Exception('Failed to get random message: ${randomResult['message']}');
    }
    
    final signMessageStr = randomResult['signMessage'] as String;
    print('SignMessage from server: $signMessageStr');
    
    // Sign the message
    final signature = signMessage(privateKeyBytes, signMessageStr);
    print('Generated Signature: $signature');
    
    // Cache the headers
    _cachedAuthHeaders = {
      'x-message': signMessageStr,
      'x-signature': signature,
      'x-address': address,
    };
    _cachedAddress = address;
    _cacheExpiry = DateTime.now().add(_cacheDuration);
    
    print('=== HEADERS CACHED (valid for 4 hours) ===');
    
    return _cachedAuthHeaders!;
  }

  /// Clear cached auth headers
  void clearAuthCache() {
    _cachedAuthHeaders = null;
    _cachedAddress = null;
    _cacheExpiry = null;
    print('Auth cache cleared');
  }

  /// Convert BigInt to bytes (minimal encoding)
  Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List(0);
    }
    
    var hex = value.toRadixString(16);
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    
    return _hexToBytes('0x$hex');
  }

  /// Simple RLP encode for a list of byte arrays
  Uint8List _rlpEncode(List<Uint8List> items) {
    final encodedItems = <int>[];
    
    for (final item in items) {
      if (item.length == 1 && item[0] < 0x80) {
        encodedItems.add(item[0]);
      } else if (item.isEmpty) {
        encodedItems.add(0x80);
      } else if (item.length <= 55) {
        encodedItems.add(0x80 + item.length);
        encodedItems.addAll(item);
      } else {
        final lengthBytes = _bigIntToBytes(BigInt.from(item.length));
        encodedItems.add(0xb7 + lengthBytes.length);
        encodedItems.addAll(lengthBytes);
        encodedItems.addAll(item);
      }
    }
    
    if (encodedItems.length <= 55) {
      return Uint8List.fromList([0xc0 + encodedItems.length, ...encodedItems]);
    } else {
      final lengthBytes = _bigIntToBytes(BigInt.from(encodedItems.length));
      return Uint8List.fromList([0xf7 + lengthBytes.length, ...lengthBytes, ...encodedItems]);
    }
  }

  /// Create authorization data for EIP-7702
  Map<String, dynamic> createAuthorizationData(Uint8List privateKeyBytes, int nonce) {
    final chainIdBig = BigInt.from(config.chainId);
    final nonceBig = BigInt.from(nonce);
    
    final codeAddressBytes = _hexToBytes(config.delegateAddress);
    final rlpData = _rlpEncode([
      _bigIntToBytes(chainIdBig),
      codeAddressBytes,
      _bigIntToBytes(nonceBig),
    ]);
    
    final preimage = Uint8List(1 + rlpData.length);
    preimage[0] = 0x05;
    preimage.setAll(1, rlpData);
    
    final credentials = EthPrivateKey(privateKeyBytes);
    final signature = credentials.signToEcSignature(preimage);
    
    final v = signature.v;
    final r = '0x${signature.r.toRadixString(16).padLeft(64, '0')}';
    final s = '0x${signature.s.toRadixString(16).padLeft(64, '0')}';
    
    print('=== AUTHORIZATION DATA ===');
    print('Chain ID: ${config.chainId}');
    print('Code Address: ${config.delegateAddress}');
    print('Nonce: $nonce');
    print('v: $v');
    print('r: $r');
    print('s: $s');
    
    return {
      'address': config.delegateAddress,
      'nonce': nonce.toString(),
      'chainId': config.chainId.toString(),
      'signature': {
        '_type': 'signature',
        'networkV': null,
        'r': r,
        's': s,
        'v': v,
      },
    };
  }

  /// Register wallet with the backend
  Future<Eip7702Result> registerWallet(Uint8List privateKeyBytes) async {
    try {
      print('\n=== REGISTER WALLET ===');
      
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.registerWallet(headers);
      
      clearAuthCache();
      
      if (result['success'] == true || result['message']?.contains('already') == true) {
        return Eip7702Result.success(data: result);
      } else {
        return Eip7702Result.failure(result['message'] ?? 'Registration failed');
      }
    } catch (e) {
      print('Error in registerWallet: $e');
      return Eip7702Result.failure('Registration failed: $e');
    }
  }

  /// Admin whitelist an address
  Future<Eip7702Result> adminWhitelist(
    Uint8List privateKeyBytes,
    String secretApiKey,
    String walletAddress,
  ) async {
    try {
      print('\n=== ADMIN WHITELIST ===');
      print('Wallet to whitelist: $walletAddress');
      print('API Key present: ${secretApiKey.isNotEmpty}');
      
      // Create auth headers with signature
      final authHeaders = await createAuthHeaders(privateKeyBytes);
      
      // Add API key to headers
      final headers = {
        ...authHeaders,
        'x-api-key': secretApiKey,
      };
      
      print('Headers: $headers');
      
      final result = await _api.adminWhitelist(walletAddress, headers);
      
      print('Whitelist result: $result');
      
      if (result['success'] == true) {
        return Eip7702Result.success(data: result);
      } else {
        return Eip7702Result.failure(result['message'] ?? 'Failed to whitelist wallet');
      }
    } catch (e) {
      print('Error in adminWhitelist: $e');
      return Eip7702Result.failure('Admin whitelist failed: $e');
    }
  }

  /// Register and whitelist in one call
  Future<Eip7702Result> registerAndWhitelist(Uint8List privateKeyBytes, String secretApiKey) async {
    print('');
    print('=== REGISTER AND WHITELIST START ===');
    print('API Key provided: ${secretApiKey.isNotEmpty}');
    
    final registerResult = await registerWallet(privateKeyBytes);
    
    print('Register result - success: ${registerResult.success}');
    print('Register result - error: ${registerResult.error}');
    print('Register result - data: ${registerResult.data}');
    
    // Check if we should continue to whitelist
    final shouldContinue = registerResult.success || 
        (registerResult.error?.toLowerCase().contains('already') == true) ||
        (registerResult.data?['message']?.toString().toLowerCase().contains('already') == true);
    
    print('Should continue to whitelist: $shouldContinue');
    
    if (!shouldContinue) {
      print('Stopping - registration failed');
      return registerResult;
    }
    
    final address = getAddressFromPrivateKey(privateKeyBytes);
    print('Proceeding to whitelist address: $address');
    
    final whitelistResult = await adminWhitelist(privateKeyBytes, secretApiKey, address);
    
    print('=== REGISTER AND WHITELIST END ===');
    return whitelistResult;
  }
  
  /// Authorize wallet for EIP-7702
  Future<Eip7702Result> authorize(Uint8List privateKeyBytes, {bool waitForTx = false}) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      
      final credentials = EthPrivateKey(privateKeyBytes);
      final walletAddress = _toChecksumAddress(credentials.address.toString().replaceAll('0x', ''));
      
      print('=== AUTHORIZE DEBUG ===');
      print('Wallet address (checksummed): $walletAddress');
      
      int nonce = 0;
      try {
        final nonceResult = await _api.getWalletNonce(headers);
        print('Nonce result: $nonceResult');
        if (nonceResult['success'] == true) {
          final nonceValue = nonceResult['delegationNonce'] ?? nonceResult['nonce'] ?? nonceResult['result'] ?? 0;
          if (nonceValue is String) {
            nonce = int.tryParse(nonceValue) ?? 0;
          } else if (nonceValue is int) {
            nonce = nonceValue;
          }
        }
        print('Using nonce: $nonce');
      } catch (e) {
        print('Failed to get nonce, using 0: $e');
      }
      
      final authData = createAuthorizationData(privateKeyBytes, nonce);
      
      print('=== SENDING AUTHORIZATION ===');
      print('Auth: $authData');
      print('Wallet address: $walletAddress');
      print('waitForTx: $waitForTx');
      
      final result = await _api.authorizeTransaction(
        authData, 
        headers, 
        walletAddress: walletAddress,
        waitForTx: waitForTx,
      );
      
      print('Authorization response: $result');
      
      if (result['success'] == true || result['transaction'] != null) {
        final tx = result['transaction'] as Map<String, dynamic>?;
        return Eip7702Result.success(
          txHash: tx?['hash'] ?? tx?['txHash'],
          transactionId: tx?['id'],
          data: result,
        );
      } else {
        return Eip7702Result.failure(result['message'] ?? 'Authorization failed');
      }
    } catch (e) {
      print('Authorization error: $e');
      return Eip7702Result.failure(e.toString());
    }
  }

  /// Get wallet status
  Future<Eip7702Result> getWalletStatus(Uint8List privateKeyBytes) async {
    try {
      clearAuthCache();
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.getWalletStatus(headers);
      
      if (result['success'] == true) {
        return Eip7702Result.success(data: result);
      } else {
        return Eip7702Result.failure(result['message'] ?? 'Failed to get status');
      }
    } catch (e) {
      print('Error in getWalletStatus: $e');
      return Eip7702Result.failure('Failed to get wallet status: $e');
    }
  }

  /// Get OroCash balance using API key
  Future<BigInt> getOroCashBalanceWithApiKey(String address, String apiKey) async {
    try {
      final headers = {'x-api-key': apiKey};
      final result = await _api.getBalance(address, headers);
      
      if (result['balance'] != null) {
        return BigInt.parse(result['balance'].toString());
      }
      return BigInt.zero;
    } catch (e) {
      print('Error getting balance: $e');
      return BigInt.zero;
    }
  }

  /// Get formatted balance with API key (uses cached decimals)
  Future<String> getOroCashBalanceFormattedWithApiKey(String address, String apiKey) async {
    final balance = await getOroCashBalanceWithApiKey(address, apiKey);
    return formatAmount(balance);
  }

  /// Get wallet nonce
  Future<Eip7702Result> getWalletNonce(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.getWalletNonce(headers);
      
      if (result['success'] == true) {
        return Eip7702Result.success(data: result);
      } else {
        return Eip7702Result.failure(result['message'] ?? 'Failed to get nonce');
      }
    } catch (e) {
      return Eip7702Result.failure(e.toString());
    }
  }

  /// Execute a gasless transaction
  Future<Eip7702Result> executeGasless(
    Uint8List privateKeyBytes,
    String to,
    String data, {
    BigInt? value,
    bool waitForTx = false,
  }) async {
    return executeBatchGasless(
      privateKeyBytes,
      [BatchCall(to: to, data: data, value: value)],
      waitForTx: waitForTx,
    );
  }

  /// Execute batch gasless transactions
  Future<Eip7702Result> executeBatchGasless(
    Uint8List privateKeyBytes,
    List<BatchCall> calls, {
    bool waitForTx = false,
  }) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      
      final nonceResult = await _api.getWalletNonce(headers);
      final delegationNonceRaw = nonceResult['delegationNonce'] ?? 0;
      final delegationNonce = delegationNonceRaw is int 
          ? delegationNonceRaw 
          : int.parse(delegationNonceRaw.toString());
      
      print('=== BATCH GASLESS TRANSACTION ===');
      print('Delegation Nonce: $delegationNonce');
      
      List<List<dynamic>> callsArray = [];
      String encodedCalls = '';
      
      for (final call in calls) {
        final to = call.to;
        final value = call.value ?? BigInt.zero;
        final data = call.data;
        
        callsArray.add([to, value.toString(), data]);
        
        final packed = _solidityPacked(['address', 'uint256', 'bytes'], [to, value, data]);
        encodedCalls += packed.substring(2);
      }
      
      print('Calls: $callsArray');
      print('Encoded calls: 0x$encodedCalls');
      
      final digestPreimage = _solidityPacked(
        ['uint256', 'bytes'], 
        [BigInt.from(delegationNonce), '0x$encodedCalls']
      );
      print('Digest preimage: $digestPreimage');
      
      final digest = _keccak256(_hexToBytes(digestPreimage));
      print('Digest: ${_bytesToHex(digest)}');
      
      final credentials = EthPrivateKey(privateKeyBytes);
      final signature = credentials.signPersonalMessageToUint8List(digest);
      final signatureHex = '0x${_bytesToHex(signature, include0x: false)}';
      
      print('Signature: $signatureHex');
      
      final result = await _api.sponsorTransaction(
        callsArray, 
        signatureHex, 
        headers, 
        waitForTx: waitForTx,
      );
      
      if (result['success'] == true || result['transaction'] != null) {
        final tx = result['transaction'] as Map<String, dynamic>?;
        return Eip7702Result.success(
          txHash: tx?['hash'] ?? tx?['txHash'],
          transactionId: tx?['id'],
          data: result,
        );
      } else {
        return Eip7702Result.failure(result['message'] ?? 'Batch transaction failed');
      }
    } catch (e) {
      print('Batch gasless transaction error: $e');
      return Eip7702Result.failure(e.toString());
    }
  }

  /// Helper: solidityPacked implementation
  String _solidityPacked(List<String> types, List<dynamic> values) {
    String result = '0x';
    
    for (int i = 0; i < types.length; i++) {
      final type = types[i];
      final value = values[i];
      
      if (type == 'address') {
        String addr = value.toString().toLowerCase();
        if (addr.startsWith('0x')) addr = addr.substring(2);
        result += addr.padLeft(40, '0');
      } else if (type == 'uint256') {
        BigInt val;
        if (value is BigInt) {
          val = value;
        } else if (value is int) {
          val = BigInt.from(value);
        } else if (value is String) {
          val = BigInt.parse(value);
        } else {
          val = BigInt.zero;
        }
        result += val.toRadixString(16).padLeft(64, '0');
      } else if (type == 'bytes') {
        String data = value.toString();
        if (data.startsWith('0x')) data = data.substring(2);
        result += data;
      }
    }
    
    return result;
  }

  /// Get delegation status via direct RPC
  Future<DelegationStatus> getDelegationStatus(Uint8List privateKeyBytes) async {
    try {
      final address = getAddressFromPrivateKey(privateKeyBytes);
      final code = await _makeDirectRpcCall('eth_getCode', [address, 'latest']);
      
      if (code != null && code.startsWith('0xef0100')) {
        final delegateAddr = '0x${code.substring(8, 48)}';
        return DelegationStatus(
          isDelegated: true,
          delegateAddress: _toChecksumAddress(delegateAddr),
        );
      }
      
      return const DelegationStatus(isDelegated: false);
    } catch (e) {
      print('Failed to get delegation status: $e');
      return const DelegationStatus(isDelegated: false);
    }
  }

  /// Make direct RPC call
  Future<String?> _makeDirectRpcCall(String method, List<dynamic> params) async {
    try {
      final response = await http.post(
        Uri.parse(config.rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': method,
          'params': params,
          'id': 1,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['result'] as String?;
      }
      return null;
    } catch (e) {
      print('RPC error: $e');
      return null;
    }
  }

  // ============================================
  // GOLD PRICE METHODS
  // ============================================

  /// Fetch gold price (price of 1mg of gold in USD = price of 1 OROCASH token)
  Future<GoldPriceResult> getGoldPrice(Uint8List privateKeyBytes, {bool forceRefresh = false}) async {
    try {
      // Check cache first
      if (!forceRefresh && _isGoldPriceCacheValid()) {
        print('=== USING CACHED GOLD PRICE ===');
        return GoldPriceResult.success(_cachedGoldPrice!);
      }
      
      print('=== FETCHING GOLD PRICE ===');
      
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.getGoldPrice(headers);
      
      if (result['success'] == true) {
        final price = _extractGoldPrice(result);
        print('Gold price per mg: \$${price.toStringAsFixed(6)}');
        print('Gold price per gram: \$${(price * 1000).toStringAsFixed(2)}');
        
        final goldPrice = GoldPrice(
          pricePerMg: price,
          fetchedAt: DateTime.now(),
        );
        
        // Cache the result
        _cachedGoldPrice = goldPrice;
        _goldPriceCacheExpiry = DateTime.now().add(_goldPriceCacheDuration);
        
        return GoldPriceResult.success(goldPrice);
      } else {
        return GoldPriceResult.failure(result['message'] ?? 'Failed to fetch gold price');
      }
    } catch (e) {
      print('Error fetching gold price: $e');
      return GoldPriceResult.failure('Failed to fetch gold price: $e');
    }
  }
  /// Check if gold price cache is valid
  bool _isGoldPriceCacheValid() {
    if (_cachedGoldPrice == null || _goldPriceCacheExpiry == null) return false;
    return DateTime.now().isBefore(_goldPriceCacheExpiry!);
  }

  /// Clear gold price cache
  void clearGoldPriceCache() {
    _cachedGoldPrice = null;
    _goldPriceCacheExpiry = null;
    print('Gold price cache cleared');
  }

  /// Get cached gold price (returns null if not cached or expired)
  GoldPrice? get cachedGoldPrice {
    if (_isGoldPriceCacheValid()) {
      return _cachedGoldPrice;
    }
    return null;
  }

  /// Extract price from API response
  double _extractGoldPrice(Map<String, dynamic> data) {
    // Try different response structures
    if (data.containsKey('price')) {
      final price = data['price'];
      if (price is num) return price.toDouble();
      if (price is String) return double.tryParse(price) ?? 0.0;
    }
    
    if (data.containsKey('result')) {
      final result = data['result'];
      if (result is num) return result.toDouble();
      if (result is String) return double.tryParse(result) ?? 0.0;
      if (result is Map) {
        if (result.containsKey('price')) {
          final price = result['price'];
          if (price is num) return price.toDouble();
          if (price is String) return double.tryParse(price) ?? 0.0;
        }
        if (result.containsKey('pricePerMg')) {
          final price = result['pricePerMg'];
          if (price is num) return price.toDouble();
          if (price is String) return double.tryParse(price) ?? 0.0;
        }
      }
    }
    
    if (data.containsKey('data')) {
      final d = data['data'];
      if (d is Map) {
        if (d.containsKey('price')) {
          final price = d['price'];
          if (price is num) return price.toDouble();
          if (price is String) return double.tryParse(price) ?? 0.0;
        }
      }
    }
    
    throw Exception('Unable to extract gold price from response: $data');
  }

  /// Calculate USD value from token balance string
  double calculateTokenUsdValue(String balance, double pricePerMg) {
    final balanceNum = double.tryParse(balance.replaceAll(',', '')) ?? 0.0;
    return balanceNum * pricePerMg;
  }

  /// Calculate USD value from raw BigInt balance
  double calculateTokenUsdValueFromRaw(BigInt balance, double pricePerMg) {
    final humanBalance = toHumanAmount(balance);
    return humanBalance * pricePerMg;
  }

  /// Format USD value for display
  String formatUsdValue(double value) {
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      final formatted = value.toStringAsFixed(2);
      final parts = formatted.split('.');
      final intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      return '\$$intPart.${parts[1]}';
    }
    return '\$${value.toStringAsFixed(2)}';
  }

  /// Get balance with USD value (convenience method)
  Future<Map<String, dynamic>> getBalanceWithUsdValue(
    Uint8List privateKeyBytes,
    String address,
    String apiKey,
  ) async {
    try {
      final balance = await getOroCashBalanceFormattedWithApiKey(address, apiKey);
      final priceResult = await getGoldPrice(privateKeyBytes);
      
      if (priceResult.success && priceResult.price != null) {
        final usdValue = calculateTokenUsdValue(balance, priceResult.price!.pricePerMg);
        return {
          'success': true,
          'balance': balance,
          'usdValue': usdValue,
          'formattedUsdValue': formatUsdValue(usdValue),
          'goldPrice': priceResult.price,
        };
      }
      
      return {
        'success': true,
        'balance': balance,
        'usdValue': null,
        'formattedUsdValue': null,
        'goldPrice': null,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ============================================
  // CONTRACT READ METHODS (via API)
  // ============================================

  /// Get OroCash balance with signature
  Future<BigInt> getOroCashBalanceWithSignature(Uint8List privateKeyBytes, String address) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('balanceOf', headers, params: [address]);
    if (result['success'] == true) {
      final value = result['result']?.toString() ?? '0';
      return BigInt.tryParse(value) ?? BigInt.zero;
    }
    throw Exception('OroCash read failed: ${result['message']}');
  }

  // Alias methods for backward compatibility
  Future<String> getOroCashNameWithSignature(Uint8List privateKeyBytes) async {
    return getTokenName(privateKeyBytes);
  }

  Future<String> getOroCashSymbolWithSignature(Uint8List privateKeyBytes) async {
    return getTokenSymbol(privateKeyBytes);
  }

  Future<int> getOroCashDecimalsWithSignature(Uint8List privateKeyBytes) async {
    return getTokenDecimals(privateKeyBytes);
  }

  Future<BigInt> getOroCashTotalSupplyWithSignature(Uint8List privateKeyBytes) async {
    return getTotalSupply(privateKeyBytes);
  }

  /// Get OroCash balance from wallet
  Future<BigInt> getOroCashBalanceFromWallet(Uint8List privateKeyBytes) async {
    final address = getAddressFromPrivateKey(privateKeyBytes);
    return getOroCashBalanceWithSignature(privateKeyBytes, address);
  }

  /// Get formatted OroCash balance from wallet (uses cached decimals)
  Future<double> getOroCashBalanceFromWalletFormatted(Uint8List privateKeyBytes) async {
    final rawBalance = await getOroCashBalanceFromWallet(privateKeyBytes);
    return toHumanAmount(rawBalance);
  }

  /// Get token name
  Future<String> getTokenName(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('name', headers);
    if (result['success'] == true) {
      return result['result']?.toString() ?? '';
    }
    throw Exception('Failed to get token name: ${result['message']}');
  }

  /// Get token symbol
  Future<String> getTokenSymbol(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('symbol', headers);
    if (result['success'] == true) {
      return result['result']?.toString() ?? '';
    }
    throw Exception('Failed to get token symbol: ${result['message']}');
  }

  /// Get token decimals
  Future<int> getTokenDecimals(Uint8List privateKeyBytes) async {
    if (_isInitialized) {
      return _tokenDecimals;
    }
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('decimals', headers);
    if (result['success'] == true) {
      return int.tryParse(result['result']?.toString() ?? '6') ?? 6;
    }
    throw Exception('Failed to get decimals: ${result['message']}');
  }

  /// Get total supply
  Future<BigInt> getTotalSupply(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('totalSupply', headers);
    if (result['success'] == true) {
      return BigInt.tryParse(result['result']?.toString() ?? '0') ?? BigInt.zero;
    }
    throw Exception('Failed to get total supply: ${result['message']}');
  }

  /// Get contract owner
  Future<String> getOwner(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('owner', headers);
    if (result['success'] == true) {
      return result['result']?.toString() ?? '';
    }
    throw Exception('Failed to get owner: ${result['message']}');
  }

  /// Check if contract is paused
  Future<bool> isPaused(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('Paused', headers);
    if (result['success'] == true) {
      final value = result['result'];
      if (value is bool) return value;
      return value?.toString().toLowerCase() == 'true';
    }
    throw Exception('Failed to get paused status: ${result['message']}');
  }

  /// Check if custody is enabled
  Future<bool> isCustodyEnabled(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('CustodyEnable', headers);
    if (result['success'] == true) {
      final value = result['result'];
      if (value is bool) return value;
      return value?.toString().toLowerCase() == 'true';
    }
    throw Exception('Failed to get custody status: ${result['message']}');
  }

  /// Check if fee is enabled
  Future<bool> hasFee(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('HasFee', headers);
    if (result['success'] == true) {
      final value = result['result'];
      if (value is bool) return value;
      return value?.toString().toLowerCase() == 'true';
    }
    throw Exception('Failed to get fee status: ${result['message']}');
  }

  /// Check if limit tx is enabled
  Future<bool> isLimitTxEnabled(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('LimitTx', headers);
    if (result['success'] == true) {
      final value = result['result'];
      if (value is bool) return value;
      return value?.toString().toLowerCase() == 'true';
    }
    throw Exception('Failed to get limit tx status: ${result['message']}');
  }

  /// Get minimum hold token amount
  Future<BigInt> getMinHoldToken(Uint8List privateKeyBytes) async {
    final headers = await createAuthHeaders(privateKeyBytes);
    final result = await _api.oroCashRead('MinHoldToken', headers);
    if (result['success'] == true) {
      return BigInt.tryParse(result['result']?.toString() ?? '0') ?? BigInt.zero;
    }
    throw Exception('Failed to get min hold token: ${result['message']}');
  }

  // ============================================
  // FEES
  // ============================================

  /// Get percent fee in basis points (100 = 1%, 10000 = 100%)
  Future<BigInt> getPercentFeeBps(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('percentFeeBps', headers);
      if (result['success'] == true) {
        return BigInt.tryParse(result['result']?.toString() ?? '0') ?? BigInt.zero;
      }
      return BigInt.zero;
    } catch (e) {
      print('Error getting percentFeeBps: $e');
      return BigInt.zero;
    }
  }

  /// Get percent fee as human-readable percentage (e.g., 3.5 for 3.5%)
  Future<double> getPercentFeePercent(Uint8List privateKeyBytes) async {
    final bps = await getPercentFeeBps(privateKeyBytes);
    return bps.toDouble() / 100; // 100 bps = 1%
  }

  /// Get fixed fee (raw amount)
  Future<BigInt> getFixedFee(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('fixedFee', headers);
      if (result['success'] == true) {
        return BigInt.tryParse(result['result']?.toString() ?? '0') ?? BigInt.zero;
      }
      return BigInt.zero;
    } catch (e) {
      print('Error getting fixedFee: $e');
      return BigInt.zero;
    }
  }

  /// Get fixed fee formatted (human-readable)
  Future<String> getFixedFeeFormatted(Uint8List privateKeyBytes) async {
    final fee = await getFixedFee(privateKeyBytes);
    return formatAmount(fee);
  }

  // ============================================
  // TRANSACTION LIMITS
  // ============================================

  /// Get user limit (min, max) for a specific address
  Future<List<BigInt>> getUserLimit(Uint8List privateKeyBytes, String userAddress) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('getUserLimit', headers, params: [userAddress]);
      
      if (result['success'] == true) {
        final data = result['result'];
        
        if (data is List && data.length >= 2) {
          return [
            BigInt.tryParse(data[0].toString()) ?? BigInt.zero,
            BigInt.tryParse(data[1].toString()) ?? BigInt.zero,
          ];
        }
        
        if (data is Map) {
          final min = data['0'] ?? data['min'] ?? data[0] ?? BigInt.zero;
          final max = data['1'] ?? data['max'] ?? data[1] ?? BigInt.zero;
          return [
            BigInt.tryParse(min.toString()) ?? BigInt.zero,
            BigInt.tryParse(max.toString()) ?? BigInt.zero,
          ];
        }
      }
      return [BigInt.zero, BigInt.zero];
    } catch (e) {
      print('Error getting user limit for $userAddress: $e');
      return [BigInt.zero, BigInt.zero];
    }
  }

  /// Get user limit min for a specific address
  Future<BigInt> getUserLimitMin(Uint8List privateKeyBytes, String userAddress) async {
    final limits = await getUserLimit(privateKeyBytes, userAddress);
    return limits[0];
  }

  /// Get user limit max for a specific address
  Future<BigInt> getUserLimitMax(Uint8List privateKeyBytes, String userAddress) async {
    final limits = await getUserLimit(privateKeyBytes, userAddress);
    return limits[1];
  }

  /// Get global tx limit min (arg 0)
  Future<BigInt> getTxLimitGlobalMin(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('TxLimitGLobal', headers, params: [0]);
      if (result['success'] == true) {
        return BigInt.tryParse(result['result']?.toString() ?? '0') ?? BigInt.zero;
      }
      return BigInt.zero;
    } catch (e) {
      print('Error getting TxLimitGlobalMin: $e');
      return BigInt.zero;
    }
  }

  /// Get global tx limit max (arg 1)
  Future<BigInt> getTxLimitGlobalMax(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('TxLimitGLobal', headers, params: [1]);
      if (result['success'] == true) {
        return BigInt.tryParse(result['result']?.toString() ?? '0') ?? BigInt.zero;
      }
      return BigInt.zero;
    } catch (e) {
      print('Error getting TxLimitGlobalMax: $e');
      return BigInt.zero;
    }
  }

  // ============================================
  // NONCES AND DELEGATION
  // ============================================

  /// Get delegated nonces from the nonce endpoint
  Future<Map<String, int>> getDelegatedNoncesWithSignature(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.getWalletNonce(headers);
      
      if (result['success'] == true) {
        return {
          'nonce': _toInt(result['nonce']),
          'goldNonce': _toInt(result['goldNonce']),
          'delegationNonce': _toInt(result['delegationNonce']),
        };
      }
      return {'nonce': 0, 'goldNonce': 0, 'delegationNonce': 0};
    } catch (e) {
      print('Error getting delegated nonces: $e');
      return {'nonce': 0, 'goldNonce': 0, 'delegationNonce': 0};
    }
  }

  /// Helper to safely convert to int
  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  // ============================================
  // ROLES
  // ============================================

  static const Map<int, String> roleNames = {
    0: 'Admin',
    1: 'Moderator',
    2: 'Minter',
    3: 'Extractor',
    4: 'CFO',
    5: 'Whitelist',
  };

  /// Check if user has a specific role
  Future<bool> hasRole(Uint8List privateKeyBytes, int roleId, String account) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('hasRole', headers, params: [roleId, account]);
      if (result['success'] == true) {
        final value = result['result'];
        if (value is bool) return value;
        return value?.toString().toLowerCase() == 'true';
      }
      return false;
    } catch (e) {
      print('Error checking role $roleId for $account: $e');
      return false;
    }
  }

  /// Get all user roles
  Future<Map<int, bool>> getUserRoles(Uint8List privateKeyBytes, String address) async {
    final roles = <int, bool>{};
    
    for (int roleId = 0; roleId <= 5; roleId++) {
      try {
        final hasRoleResult = await hasRole(privateKeyBytes, roleId, address);
        roles[roleId] = hasRoleResult;
      } catch (e) {
        print('Error checking role $roleId: $e');
        roles[roleId] = false;
      }
    }
    return roles;
  }

  /// Get role name from role ID
  static String getRoleName(int roleId) {
    return roleNames[roleId] ?? 'Unknown';
  }

  /// Get all contract info
  Future<Map<String, dynamic>> getAllContractInfo(Uint8List privateKeyBytes) async {
    final results = <String, dynamic>{};
    final address = getAddressFromPrivateKey(privateKeyBytes);

    // Token info
    try { results['name'] = await getTokenName(privateKeyBytes); } catch (e) { results['name'] = ''; }
    try { results['symbol'] = await getTokenSymbol(privateKeyBytes); } catch (e) { results['symbol'] = ''; }
    try { results['decimals'] = await getTokenDecimals(privateKeyBytes); } catch (e) { results['decimals'] = 6; }
    try { results['totalSupply'] = await getTotalSupply(privateKeyBytes); } catch (e) { results['totalSupply'] = BigInt.zero; }
    try { results['balance'] = await getOroCashBalanceFromWallet(privateKeyBytes); } catch (e) { results['balance'] = BigInt.zero; }
    try { results['owner'] = await getOwner(privateKeyBytes); } catch (e) { results['owner'] = ''; }
    
    // Contract state
    try { results['isPaused'] = await isPaused(privateKeyBytes); } catch (e) { results['isPaused'] = false; }
    try { results['custodyEnabled'] = await isCustodyEnabled(privateKeyBytes); } catch (e) { results['custodyEnabled'] = false; }
    try { results['hasFee'] = await hasFee(privateKeyBytes); } catch (e) { results['hasFee'] = false; }
    try { results['limitTxEnabled'] = await isLimitTxEnabled(privateKeyBytes); } catch (e) { results['limitTxEnabled'] = false; }
    try { results['minHoldToken'] = await getMinHoldToken(privateKeyBytes); } catch (e) { results['minHoldToken'] = BigInt.zero; }
    
    // Fees (updated for new contract - basis points)
    try { results['percentFeeBps'] = await getPercentFeeBps(privateKeyBytes); } catch (e) { results['percentFeeBps'] = BigInt.zero; }
    try { results['percentFeePercent'] = await getPercentFeePercent(privateKeyBytes); } catch (e) { results['percentFeePercent'] = 0.0; }
    try { results['fixedFee'] = await getFixedFee(privateKeyBytes); } catch (e) { results['fixedFee'] = BigInt.zero; }
    
    // Limits
    try { results['txLimitGlobalMin'] = await getTxLimitGlobalMin(privateKeyBytes); } catch (e) { results['txLimitGlobalMin'] = BigInt.zero; }
    try { results['txLimitGlobalMax'] = await getTxLimitGlobalMax(privateKeyBytes); } catch (e) { results['txLimitGlobalMax'] = BigInt.zero; }
    
    // Nonces
    try { 
      final nonces = await getDelegatedNoncesWithSignature(privateKeyBytes);
      results['delegatedNonces'] = nonces['delegationNonce'];
      results['authorizationNonce'] = nonces['nonce'];
    } catch (e) { 
      results['delegatedNonces'] = 0;
      results['authorizationNonce'] = 0;
    }
    
    // Roles
    try { results['roles'] = await getUserRoles(privateKeyBytes, address); } catch (e) { results['roles'] = <int, bool>{}; }
    
    // Gold price
    try {
      final goldPriceResult = await getGoldPrice(privateKeyBytes);
      if (goldPriceResult.success && goldPriceResult.price != null) {
        results['goldPrice'] = goldPriceResult.price;
        final balance = results['balance'] as BigInt?;
        if (balance != null) {
          results['balanceUsdValue'] = calculateTokenUsdValueFromRaw(balance, goldPriceResult.price!.pricePerMg);
        }
      }
    } catch (e) {
      results['goldPrice'] = null;
      results['balanceUsdValue'] = null;
    }

    // NFT Membership
    try { 
      final membershipInfo = await getWalletMembershipInfo(privateKeyBytes);
      results['membership'] = {
        'isMember': membershipInfo.isMember,
        'tokenId': membershipInfo.tokenId.toString(),
        'mintedAt': membershipInfo.isMember ? membershipInfo.mintedAt.toIso8601String() : '',
        'tokenURI': membershipInfo.tokenURI,
      };
    } catch (e) { 
      results['membership'] = {
        'isMember': false,
        'tokenId': '0',
        'mintedAt': '',
        'tokenURI': '',
      };
    }
    
    try { results['totalMemberships'] = await totalMemberships(privateKeyBytes); } catch (e) { results['totalMemberships'] = BigInt.zero; }
    try { results['nftName'] = await getNftName(privateKeyBytes); } catch (e) { results['nftName'] = ''; }
    try { results['nftSymbol'] = await getNftSymbol(privateKeyBytes); } catch (e) { results['nftSymbol'] = ''; }
    try { results['nftBaseURI'] = await getNftBaseURI(privateKeyBytes); } catch (e) { results['nftBaseURI'] = ''; }

    results['address'] = address;
    return results;
  }
  // ============================================
  // ABI ENCODING HELPERS
  // ============================================

  String _encodeTransferCall(String to, BigInt amount) {
    const selector = 'a9059cbb';
    final toParam = to.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
    final amountParam = amount.toRadixString(16).padLeft(64, '0');
    return '0x$selector$toParam$amountParam';
  }

  String _encodeTransferFromCall(String from, String to, BigInt amount) {
    const selector = '23b872dd';
    final fromParam = from.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
    final toParam = to.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
    final amountParam = amount.toRadixString(16).padLeft(64, '0');
    return '0x$selector$fromParam$toParam$amountParam';
  }

  String _encodeApproveCall(String spender, BigInt amount) {
    const selector = '095ea7b3';
    final spenderParam = spender.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
    final amountParam = amount.toRadixString(16).padLeft(64, '0');
    return '0x$selector$spenderParam$amountParam';
  }

  String _encodeBuyTokenCall(String to, BigInt amount) {
    const selector = '68f8fc10';
    final toParam = to.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
    final amountParam = amount.toRadixString(16).padLeft(64, '0');
    return '0x$selector$toParam$amountParam';
  }

  String _encodeSellTokenCall(String to, BigInt amount) {
    const selector = 'f464e7db';
    final toParam = to.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');
    final amountParam = amount.toRadixString(16).padLeft(64, '0');
    return '0x$selector$toParam$amountParam';
  }

  String _encodeDisposeTokenCall(BigInt amount) {
    const selector = '18e9c824';
    final amountParam = amount.toRadixString(16).padLeft(64, '0');
    return '0x$selector$amountParam';
  }

  // ============================================
  // PUBLIC WRITE METHODS
  // ============================================

  /// Transfer tokens (raw BigInt amount)
  Future<Eip7702Result> transferOroCash(
    Uint8List privateKeyBytes,
    String contractAddress,
    String toAddress,
    BigInt amount, {
    bool waitForTx = false,
  }) async {
    print('=== TRANSFER ===');
    print('To: $toAddress');
    print('Raw amount: $amount');
    
    final data = _encodeTransferCall(toAddress, amount);
    return executeGasless(
      privateKeyBytes,
      contractAddress,
      data,
      waitForTx: waitForTx,
    );
  }

  /// Transfer tokens with human-readable amount (e.g., 1.5 tokens)
  Future<Eip7702Result> transferOroCashFormatted(
    Uint8List privateKeyBytes,
    String contractAddress,
    String toAddress,
    double amount, {
    bool waitForTx = false,
  }) async {
    final rawAmount = toRawAmount(amount);
    
    print('=== TRANSFER FORMATTED ===');
    print('Human amount: $amount');
    print('Raw amount: $rawAmount');
    
    return transferOroCash(privateKeyBytes, contractAddress, toAddress, rawAmount, waitForTx: waitForTx);
  }

  /// Transfer tokens from another address (raw BigInt amount)
  Future<Eip7702Result> transferFrom(
    Uint8List privateKeyBytes,
    String contractAddress,
    String from,
    String to,
    BigInt amount, {
    bool waitForTx = false,
  }) async {
    final data = _encodeTransferFromCall(from, to, amount);
    return executeGasless(
      privateKeyBytes,
      contractAddress,
      data,
      waitForTx: waitForTx,
    );
  }

  /// Transfer from with human-readable amount
  Future<Eip7702Result> transferFromFormatted(
    Uint8List privateKeyBytes,
    String contractAddress,
    String from,
    String to,
    double amount, {
    bool waitForTx = false,
  }) async {
    final rawAmount = toRawAmount(amount);
    return transferFrom(privateKeyBytes, contractAddress, from, to, rawAmount, waitForTx: waitForTx);
  }

  /// Approve spender (raw BigInt amount)
  Future<Eip7702Result> approve(
    Uint8List privateKeyBytes,
    String contractAddress,
    String spender,
    BigInt amount, {
    bool waitForTx = false,
  }) async {
    print('=== APPROVE ===');
    print('Spender: $spender');
    print('Raw amount: $amount');
    
    final data = _encodeApproveCall(spender, amount);
    return executeGasless(
      privateKeyBytes,
      contractAddress,
      data,
      waitForTx: waitForTx,
    );
  }

  /// Approve with human-readable amount
  Future<Eip7702Result> approveFormatted(
    Uint8List privateKeyBytes,
    String contractAddress,
    String spender,
    double amount, {
    bool waitForTx = false,
  }) async {
    final rawAmount = toRawAmount(amount);
    
    print('=== APPROVE FORMATTED ===');
    print('Human amount: $amount');
    print('Raw amount: $rawAmount');
    
    return approve(privateKeyBytes, contractAddress, spender, rawAmount, waitForTx: waitForTx);
  }

  /// Approve unlimited spending (max uint256)
  Future<Eip7702Result> approveUnlimited(
    Uint8List privateKeyBytes,
    String contractAddress,
    String spender, {
    bool waitForTx = false,
  }) async {
    final maxAmount = BigInt.parse('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', radix: 16);
    return approve(privateKeyBytes, contractAddress, spender, maxAmount, waitForTx: waitForTx);
  }

  /// Buy tokens (raw BigInt amount)
  Future<Eip7702Result> buyToken(
    Uint8List privateKeyBytes,
    String contractAddress,
    String to,
    BigInt amount, {
    bool waitForTx = false,
  }) async {
    final data = _encodeBuyTokenCall(to, amount);
    return executeGasless(
      privateKeyBytes,
      contractAddress,
      data,
      waitForTx: waitForTx,
    );
  }

  /// Buy tokens with human-readable amount
  Future<Eip7702Result> buyTokenFormatted(
    Uint8List privateKeyBytes,
    String contractAddress,
    String to,
    double amount, {
    bool waitForTx = false,
  }) async {
    final rawAmount = toRawAmount(amount);
    return buyToken(privateKeyBytes, contractAddress, to, rawAmount, waitForTx: waitForTx);
  }

  /// Sell tokens (raw BigInt amount)
  Future<Eip7702Result> sellToken(
    Uint8List privateKeyBytes,
    String contractAddress,
    String to,
    BigInt amount, {
    bool waitForTx = false,
  }) async {
    final data = _encodeSellTokenCall(to, amount);
    return executeGasless(
      privateKeyBytes,
      contractAddress,
      data,
      waitForTx: waitForTx,
    );
  }

  /// Sell tokens with human-readable amount
  Future<Eip7702Result> sellTokenFormatted(
    Uint8List privateKeyBytes,
    String contractAddress,
    String to,
    double amount, {
    bool waitForTx = false,
  }) async {
    final rawAmount = toRawAmount(amount);
    return sellToken(privateKeyBytes, contractAddress, to, rawAmount, waitForTx: waitForTx);
  }

  /// Dispose (burn) tokens (raw BigInt amount)
  Future<Eip7702Result> disposeToken(
    Uint8List privateKeyBytes,
    String contractAddress,
    BigInt amount, {
    bool waitForTx = false,
  }) async {
    final data = _encodeDisposeTokenCall(amount);
    return executeGasless(
      privateKeyBytes,
      contractAddress,
      data,
      waitForTx: waitForTx,
    );
  }

  /// Dispose tokens with human-readable amount
  Future<Eip7702Result> disposeTokenFormatted(
    Uint8List privateKeyBytes,
    String contractAddress,
    double amount, {
    bool waitForTx = false,
  }) async {
    final rawAmount = toRawAmount(amount);
    return disposeToken(privateKeyBytes, contractAddress, rawAmount, waitForTx: waitForTx);
  }

  /// Get allowance for a spender
  Future<BigInt> getAllowance(
    Uint8List privateKeyBytes,
    String owner,
    String spender,
  ) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('allowance', headers, params: [owner, spender]);
      
      if (result['success'] == true && result['result'] != null) {
        return BigInt.parse(result['result'].toString());
      }
      return BigInt.zero;
    } catch (e) {
      print('Error getting allowance: $e');
      return BigInt.zero;
    }
  }

  /// Get formatted allowance (human-readable)
  Future<String> getAllowanceFormatted(
    Uint8List privateKeyBytes,
    String owner,
    String spender,
  ) async {
    final allowance = await getAllowance(privateKeyBytes, owner, spender);
    return formatAmount(allowance);
  }

  /// Admin mint tokens
  Future<Eip7702Result> adminMint(String secretApiKey, String toAddress, String amount) async {
    try {
      print('\n=== ADMIN MINT ===');
      print('To: $toAddress');
      print('Amount: $amount');
      
      final headers = {
        'x-api-key': secretApiKey,
      };
      
      final result = await _api.adminMint(toAddress, amount, headers);
      
      if (result['success'] == true) {
        return Eip7702Result.success(data: result);
      } else {
        return Eip7702Result.failure(result['message'] ?? 'Mint failed');
      }
    } catch (e) {
      print('Error in adminMint: $e');
      return Eip7702Result.failure('Admin mint failed: $e');
    }
  }

  // ============================================
  // SOULBOUND NFT READ METHODS (Public)
  // ============================================

  /// Check if address has membership NFT
  Future<bool> hasMembership(Uint8List privateKeyBytes, String address) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('hasMembership', headers, params: [address]);
      if (result['success'] == true) {
        final value = result['result'];
        if (value is bool) return value;
        return value?.toString().toLowerCase() == 'true';
      }
      return false;
    } catch (e) {
      print('Error checking membership: $e');
      return false;
    }
  }

  /// Get membership tokenId for address (returns 0 if no membership)
  Future<BigInt> membershipOf(Uint8List privateKeyBytes, String address) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('membershipOf', headers, params: [address]);
      if (result['success'] == true) {
        return BigInt.tryParse(result['result']?.toString() ?? '0') ?? BigInt.zero;
      }
      return BigInt.zero;
    } catch (e) {
      print('Error getting membershipOf: $e');
      return BigInt.zero;
    }
  }

  /// Get owner address of a membership tokenId
  Future<String> ownerOfMembership(Uint8List privateKeyBytes, BigInt tokenId) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('ownerOfMembership', headers, params: [tokenId.toString()]);
      if (result['success'] == true) {
        return result['result']?.toString() ?? '';
      }
      return '';
    } catch (e) {
      print('Error getting ownerOfMembership: $e');
      return '';
    }
  }

  /// Get total number of memberships minted
  Future<BigInt> totalMemberships(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('totalMemberships', headers);
      if (result['success'] == true) {
        return BigInt.tryParse(result['result']?.toString() ?? '0') ?? BigInt.zero;
      }
      return BigInt.zero;
    } catch (e) {
      print('Error getting totalMemberships: $e');
      return BigInt.zero;
    }
  }

  /// Get NFT balance for address (0 or 1 for soulbound)
  Future<int> nftBalanceOf(Uint8List privateKeyBytes, String address) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('nftBalanceOf', headers, params: [address]);
      if (result['success'] == true) {
        return int.tryParse(result['result']?.toString() ?? '0') ?? 0;
      }
      return 0;
    } catch (e) {
      print('Error getting nftBalanceOf: $e');
      return 0;
    }
  }

  /// Get full membership info for address
  /// Returns: {isMember, tokenId, mintedAt, tokenURI}
  Future<MembershipInfo> getMembershipInfo(Uint8List privateKeyBytes, String address) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('getMembershipInfo', headers, params: [address]);
      
      if (result['success'] == true) {
        final data = result['result'];
        
        if (data is List && data.length >= 4) {
          return MembershipInfo(
            isMember: data[0] == true || data[0] == 'true',
            tokenId: BigInt.tryParse(data[1]?.toString() ?? '0') ?? BigInt.zero,
            mintedAt: DateTime.fromMillisecondsSinceEpoch(
              (int.tryParse(data[2]?.toString() ?? '0') ?? 0) * 1000
            ),
            tokenURI: data[3]?.toString() ?? '',
          );
        }
        
        if (data is Map) {
          return MembershipInfo(
            isMember: data['isMember'] == true || data['0'] == true,
            tokenId: BigInt.tryParse(data['tokenId']?.toString() ?? data['1']?.toString() ?? '0') ?? BigInt.zero,
            mintedAt: DateTime.fromMillisecondsSinceEpoch(
              (int.tryParse(data['mintedAt']?.toString() ?? data['2']?.toString() ?? '0') ?? 0) * 1000
            ),
            tokenURI: data['tokenURI']?.toString() ?? data['3']?.toString() ?? '',
          );
        }
      }
      
      return MembershipInfo.empty();
    } catch (e) {
      print('Error getting membership info: $e');
      return MembershipInfo.empty();
    }
  }

  /// Get token URI for a specific membership tokenId
  Future<String> membershipTokenURI(Uint8List privateKeyBytes, BigInt tokenId) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('membershipTokenURI', headers, params: [tokenId.toString()]);
      if (result['success'] == true) {
        return result['result']?.toString() ?? '';
      }
      return '';
    } catch (e) {
      print('Error getting membershipTokenURI: $e');
      return '';
    }
  }

  /// Get NFT base URI
  Future<String> getNftBaseURI(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('nftBaseURI', headers);
      if (result['success'] == true) {
        return result['result']?.toString() ?? '';
      }
      return '';
    } catch (e) {
      print('Error getting nftBaseURI: $e');
      return '';
    }
  }

  /// Get NFT name
  Future<String> getNftName(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('nftName', headers);
      if (result['success'] == true) {
        return result['result']?.toString() ?? '';
      }
      return '';
    } catch (e) {
      print('Error getting nftName: $e');
      return '';
    }
  }

  /// Get NFT symbol
  Future<String> getNftSymbol(Uint8List privateKeyBytes) async {
    try {
      final headers = await createAuthHeaders(privateKeyBytes);
      final result = await _api.oroCashRead('nftSymbol', headers);
      if (result['success'] == true) {
        return result['result']?.toString() ?? '';
      }
      return '';
    } catch (e) {
      print('Error getting nftSymbol: $e');
      return '';
    }
  }

  /// Check if current wallet has membership
  Future<bool> walletHasMembership(Uint8List privateKeyBytes) async {
    final address = getAddressFromPrivateKey(privateKeyBytes);
    return hasMembership(privateKeyBytes, address);
  }

  /// Get current wallet's membership info
  Future<MembershipInfo> getWalletMembershipInfo(Uint8List privateKeyBytes) async {
    final address = getAddressFromPrivateKey(privateKeyBytes);
    return getMembershipInfo(privateKeyBytes, address);
  }

}
