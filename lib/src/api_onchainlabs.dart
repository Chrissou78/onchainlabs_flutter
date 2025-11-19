import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api.dart';

class OnchainLabsApi implements PolygonWalletApi {
  static const String base = 'https://ga-api.onchainlabs.ch';

  final http.Client _client;

  OnchainLabsApi({http.Client? client}) : _client = client ?? http.Client();

  @override
  Future<String> getRandomMessage(String address) async {
    final url = Uri.parse('$base/random');

    final res = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'address': address}),
    );

    if (res.statusCode != 200) {
      throw Exception('Error getting random message: ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    final msg = data['signMessage'];

    if (msg is! String) {
      throw Exception('Invalid API response');
    }

    return msg;
  }

  @override
  Future<String> registerWallet(String message, String signature) async {
    final url = Uri.parse('$base/register');

    final res = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'signature': signature,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Error registering wallet: ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    final addr = data['address'];

    if (addr is! String) {
      throw Exception('Invalid API response');
    }

    return addr;
  }
}
