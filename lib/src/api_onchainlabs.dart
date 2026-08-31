// lib/src/api_onchainlabs.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart';

/// Implementation of OnchainLabs API
class OnchainLabsApiImpl implements OnchainLabsApi {
  @override
  final String baseUrl;
  
  OnchainLabsApiImpl({required this.baseUrl});
  
  /// Decode a JSON object response.
  ///
  /// Always reports `httpStatusCode`, and sets `transportError: true` when the
  /// body was not a JSON object at all. Without that flag a 500 page, a
  /// captive-portal interception or a proxy error is indistinguishable from a
  /// legitimate `{success: false}` rejection by the API, and callers cannot
  /// tell a refusal from a compromised or broken channel.
  ///
  /// The body is not echoed into the message: it may be an arbitrary
  /// intercepted page, and it flows into caller error strings.
  Map<String, dynamic> _parseResponse(http.Response response) {
    final Object? decoded;
    try {
      decoded = json.decode(response.body);
    } catch (_) {
      return {
        'success': false,
        'transportError': true,
        'httpStatusCode': response.statusCode,
        'message': 'Server response was not JSON '
            '(HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes).',
      };
    }

    if (decoded is! Map<String, dynamic>) {
      return {
        'success': false,
        'transportError': true,
        'httpStatusCode': response.statusCode,
        'message': 'Server response was not a JSON object '
            '(HTTP ${response.statusCode}, got ${decoded.runtimeType}).',
      };
    }

    return {
      'httpStatusCode': response.statusCode,
      ...decoded,
    };
  }

  @override
  Future<Map<String, dynamic>> getBalance(String address, Map<String, String> headers) async {
    try {
      final url = '$baseUrl/balance/$address';
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
      final result = _parseResponse(response);
      
      
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> getRandomMessage(String address) async {
    try {
      final url = '$baseUrl/random';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'address': address}),
      );
      final result = _parseResponse(response);
      
      
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> registerWallet(Map<String, String> headers) async {
    try {
      final url = '$baseUrl/register';
      
      // Extract message and signature from headers and put in body
      final requestBody = {
        'message': headers['x-message'],
        'signature': headers['x-signature'],
      };
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      return _parseResponse(response);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> authorizeTransaction(
    Map<String, dynamic> authData,
    Map<String, String> headers, {
    String? walletAddress,
    bool waitForTx = false,
  }) async {
    try {
      final body = {
        'auth': authData,
        'waitForTx': waitForTx,
      };
      
      // Add wallet address if provided
      if (walletAddress != null) {
        body['address'] = walletAddress;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/eip7702/authorize'),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );
      
      
      return _parseResponse(response);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> sponsorTransaction(
    List<dynamic> calls,
    String signature,
    Map<String, String> headers, {
    bool waitForTx = false,
  }) async {
    try {
      final url = '$baseUrl/eip7702/sponsor';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: json.encode({
          'calls': calls,
          'signature': signature,
          'waitForTx': waitForTx,
        }),
      );
      final result = _parseResponse(response);
      
      
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> getWalletStatus(Map<String, String> headers) async {
    try {
      final url = '$baseUrl/status';
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
      final result = _parseResponse(response);
      
      
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> getWalletNonce(Map<String, String> headers) async {
    try {
      final url = '$baseUrl/nonce';
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
      final result = _parseResponse(response);
      
      
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> oroCashRead(
    String method,
    Map<String, String> headers, {
    List<dynamic>? params,
  }) async {
    try {
      final url = '$baseUrl/gold/read';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: json.encode({
          'method': method,
          if (params != null) 'params': params,
        }),
      );
      final result = _parseResponse(response);
      
      
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> adminMint(
      String toAddress, String amount, Map<String, String> headers) async {
    try {
      final url = '$baseUrl/admin/mint';
      
      final requestBody = {
        'address': toAddress,
        'amount': amount,
      };
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      return _parseResponse(response);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  @override
  Future<Map<String, dynamic>> adminWhitelist(
      String walletAddress, Map<String, String> headers) async {
    try {
      final url = '$baseUrl/admin/whitelist';
      
      final requestBody = {
        'address': walletAddress,
      };
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      return _parseResponse(response);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  @override
  Future<Map<String, dynamic>> getContracts() async {
    try {
      final url = '$baseUrl/contracts';
      
      final response = await http.get(Uri.parse(url));
      final result = _parseResponse(response);
      
      
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  @override
    Future<Map<String, dynamic>> getGoldPrice(Map<String, String> headers) async {
    try {
      final url = '$baseUrl/gold/price';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {...headers, 'Content-Type': 'application/json'},
      );
      final result = _parseResponse(response);
      
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          ...result,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch gold price: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
