// lib/src/api.dart

/// Abstract interface for OnchainLabs API
abstract class OnchainLabsApi {
  String get baseUrl;

  Future<Map<String, dynamic>> getBalance(String address, Map<String, String> headers);
  
  /// Get a random message for signing
  Future<Map<String, dynamic>> getRandomMessage(String address);
  
  /// Register a new wallet
  Future<Map<String, dynamic>> registerWallet(Map<String, String> headers);
  
  /// Authorize a transaction with EIP-7702
  Future<Map<String, dynamic>> authorizeTransaction(
    Map<String, dynamic> authData,
    Map<String, String> headers, {
    String? walletAddress,
    bool waitForTx = false,
  });
  
  Future<Map<String, dynamic>> sponsorTransaction(
    List<dynamic> calls,
    String signature,
    Map<String, String> headers, {
    bool waitForTx = false,
  });
  
  /// Get wallet status
  Future<Map<String, dynamic>> getWalletStatus(Map<String, String> headers);
  
  /// Get wallet nonce
  Future<Map<String, dynamic>> getWalletNonce(Map<String, String> headers);
  
  /// Read from OroCash contract
  Future<Map<String, dynamic>> oroCashRead(
    String method,
    Map<String, String> headers, {
    List<dynamic>? params,
  });
  
  /// Admin mint tokens
  Future<Map<String, dynamic>> adminMint(
    String toAddress,
    String amount,
    Map<String, String> headers,
  );
  
  /// Admin whitelist wallet
  Future<Map<String, dynamic>> adminWhitelist(
    String walletAddress,
    Map<String, String> headers,
  );
  
  /// Get contract addresses
  Future<Map<String, dynamic>> getContracts();
  
  /// Get gold price (price of 1mg of gold in USD = price of 1 OROCASH token)
  Future<Map<String, dynamic>> getGoldPrice(Map<String, String> headers);
}
