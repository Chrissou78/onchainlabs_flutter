import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api.dart';

class OnchainLabsApi implements PolygonWalletApi {
  static const String base = "https://ga-api.onchainlabs.ch";

  // ------------------ existing endpoints ------------------

  @override
  Future<String> getRandomMessage(String address) async {
    final url = Uri.parse("$base/random");

    final res = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"address": address}),
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to get random message "
        "(status: ${res.statusCode}, body: ${res.body})",
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final msg = data["signMessage"];
    if (msg is! String) {
      throw Exception("Invalid response from /random: ${res.body}");
    }

    return msg;
  }

  @override
  Future<String> registerWallet(String message, String signature) async {
    final url = Uri.parse("$base/register");

    final res = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "message": message,
        "signature": signature,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to register wallet "
        "(status: ${res.statusCode}, body: ${res.body})",
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final addr = data["address"];
    if (addr is! String) {
      throw Exception("Invalid response from /register: ${res.body}");
    }

    return addr;
  }

  @override
  Future<Map<String, dynamic>> mint({
    required String address,
    required String amount,
    required String message,
    required String signature,
    bool waitForTx = false,
  }) async {
    // admin/mint protected by WalletMiddleware using x-message / x-signature
    final url = Uri.parse("$base/admin/mint");

    final res = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "x-message": message,
        "x-signature": signature,
      },
      body: jsonEncode({
        "address": address,
        "amount": amount,
        "waitForTx": waitForTx,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to mint "
        "(status: ${res.statusCode}, body: ${res.body})",
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data;
  }

  // ------------------ EIP-7702 / gasless endpoints ------------------

  @override
  Future<Map<String, dynamic>> getNonces(
    Map<String, String> headers,
  ) async {
    // TS: axios.get(`${apiBase}/nonce`, { headers })
    final url = Uri.parse("$base/nonce");

    final res = await http.get(
      url,
      headers: headers,
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to get nonces "
        "(status: ${res.statusCode}, body: ${res.body})",
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data;
  }

  @override
  Future<Map<String, dynamic>> status(
    Map<String, String> headers,
  ) async {
    // TS: axios.get(`${apiBase}/status`, { headers })
    final url = Uri.parse("$base/status");

    final res = await http.get(
      url,
      headers: headers,
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to get status "
        "(status: ${res.statusCode}, body: ${res.body})",
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data;
  }

  @override
  Future<dynamic> getContractABI(String contractAddress) async {
    // TS: axios.get(`${apiBase}/abi/${address}`)
    final url = Uri.parse("$base/abi/$contractAddress");

    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to get contract ABI "
        "(status: ${res.statusCode}, body: ${res.body})",
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    // TS returns `data.abi`
    if (!data.containsKey('abi')) {
      throw Exception("Invalid ABI response: ${res.body}");
    }
    return data['abi'];
  }

  @override
  Future<Map<String, dynamic>> sponsor(
    List<List<dynamic>> calls,
    String signature,
    bool waitForTx,
    Map<String, String> headers,
  ) async {
    // TS: sponsor(calls: string, signature: string, waitForTx?: boolean, headers?)
    // POST `${apiBase}/sponsor` with body { calls, signature, waitForTx }
    // where `calls` is a JSON string (stringify(calls))
    final url = Uri.parse("$base/sponsor");

    final callsJsonString = jsonEncode(calls);

    final res = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        ...headers,
      },
      body: jsonEncode({
        "calls": callsJsonString,
        "signature": signature,
        "waitForTx": waitForTx,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(
        "Failed to sponsor gasless transaction "
        "(status: ${res.statusCode}, body: ${res.body})",
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data;
  }
}