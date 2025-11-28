import 'models.dart';

/// Low-level API interface the SDK uses.
/// You must implement this in `OnchainLabsApi`.
abstract class PolygonWalletApi {
  // ----- existing auth / random / mint -----

  Future<String> getRandomMessage(String address);

  Future<String> registerWallet(String message, String signature);

  /// Legacy HTTP mint with headers (x-message / x-signature).
  /// You can keep using this for non-gasless flows.
  Future<Map<String, dynamic>> mint({
    required String address,
    required String amount,
    required String message,
    required String signature,
    bool waitForTx = false,
  });

  // ----- EIP-7702 / gasless extras -----

  /// Returns nonces for EIP-7702 delegation:
  /// { nonce, delegationNonce }
  Future<Map<String, dynamic>> getNonces(Map<String, String> headers);

  /// Returns delegation / status info:
  /// e.g. { delegated: true, ... }
  Future<Map<String, dynamic>> status(Map<String, String> headers);

  /// Returns contract ABI JSON (string or JSON object).
  Future<dynamic> getContractABI(String contractAddress);

  /// Sponsors gasless execution.
  ///
  /// `calls` is a list of:
  ///   [contractAddress (string), value (stringified uint256), data (0x...)]
  Future<Map<String, dynamic>> sponsor(
    List<List<dynamic>> calls,
    String signature,
    bool waitForTx,
    Map<String, String> headers,
  );
}
