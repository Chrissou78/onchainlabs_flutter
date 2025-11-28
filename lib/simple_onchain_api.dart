import 'dart:convert';
import 'package:http/http.dart' as http;

/// Simple client for mint + balance using a public key as API credential.
/// Backend must accept this public key in the header (e.g. x-api-key).
class SimpleOnchainApi {
  final String baseUrl;
  final String publicKey;

  const SimpleOnchainApi({
    this.baseUrl = 'https://ga-api.onchainlabs.ch',
    required this.publicKey,
  });

  Map<String, String> get _headersJson => {
        'Content-Type': 'application/json',
        // Replace old apiKey with the public key here
        'x-api-key': publicKey,
      };

  Map<String, String> get _headersGet => {
        'x-api-key': publicKey,
      };

  /// Mint tokens to [address].
  ///
  /// [amount] must be a string in base units
  /// (contract decimals, e.g. 6 decimals = "1000000" for 1 token).
  Future<Map<String, dynamic>> mint({
    required String address,
    required String amount,
    bool waitForTx = false,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/mint');

    final body = jsonEncode({
      'address': address,
      'amount': amount,
      'waitForTx': waitForTx,
    });

    final res = await http.post(uri, headers: _headersJson, body: body);

    if (res.statusCode != 200) {
      throw Exception(
        'Mint failed: status ${res.statusCode}, body: ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data;
  }

  /// Get token balance for [address].
  ///
  /// If your API uses `GET /balance?address=...` instead of `/balance/:address`,
  /// change the Uri line below.
  Future<Map<String, dynamic>> balanceOf(String address) async {
    final uri = Uri.parse('$baseUrl/balance/$address');

    final res = await http.get(uri, headers: _headersGet);

    if (res.statusCode != 200) {
      throw Exception(
        'Balance failed: status ${res.statusCode}, body: ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data;
  }
}
