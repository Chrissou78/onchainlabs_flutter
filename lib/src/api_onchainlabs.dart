// lib/src/api_onchainlabs.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart';

/// Implementation of OnchainLabs API
class OnchainLabsApiImpl implements OnchainLabsApi {
  @override
  final String baseUrl;
  
  OnchainLabsApiImpl({required this.baseUrl});
  
  Map<String, dynamic> _parseResponse(http.Response response) {
    try {
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to parse response: ${response.body}',
      };
    }
  }

  @override
  Future<Map<String, dynamic>> getBalance(String address, Map<String, String> headers) async {
    try {
      final url = '$baseUrl/balance/$address';
      print('=== GET BALANCE ===');
      print('URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
      final result = _parseResponse(response);
      
      print('Status: ${response.statusCode}');
      print('Response: $result');
      
      return result;
    } catch (e) {
      print('getBalance error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> getRandomMessage(String address) async {
    try {
      final url = '$baseUrl/random';
      print('=== GET RANDOM MESSAGE ===');
      print('URL: $url');
      print('Address: $address');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'address': address}),
      );
      final result = _parseResponse(response);
      
      print('Status: ${response.statusCode}');
      print('Response: $result');
      
      return result;
    } catch (e) {
      print('getRandomMessage error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> registerWallet(Map<String, String> headers) async {
    try {
      print('\n=== REGISTER WALLET ===');
      final url = '$baseUrl/register';
      print('URL: $url');
      
      // Extract message and signature from headers and put in body
      final requestBody = {
        'message': headers['x-message'],
        'signature': headers['x-signature'],
      };
      print('Request body: $requestBody');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      print('Status: ${response.statusCode}');
      print('Response: ${response.body}');
      return _parseResponse(response);
    } catch (e) {
      print('Error in registerWallet: $e');
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
      
      print('Authorize response status: ${response.statusCode}');
      print('Authorize response body: ${response.body}');
      
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
      print('=== SPONSOR TRANSACTION ===');
      print('URL: $url');
      print('Calls: $calls');
      print('Signature: $signature');
      print('waitForTx: $waitForTx');
      
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
      
      print('Status: ${response.statusCode}');
      print('Response: $result');
      
      return result;
    } catch (e) {
      print('sponsorTransaction error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> getWalletStatus(Map<String, String> headers) async {
    try {
      final url = '$baseUrl/status';
      print('=== GET WALLET STATUS ===');
      print('URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
      final result = _parseResponse(response);
      
      print('Status: ${response.statusCode}');
      print('Response: $result');
      
      return result;
    } catch (e) {
      print('getWalletStatus error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> getWalletNonce(Map<String, String> headers) async {
    try {
      final url = '$baseUrl/nonce';
      print('=== GET WALLET NONCE ===');
      print('URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
      final result = _parseResponse(response);
      
      print('Status: ${response.statusCode}');
      print('Response: $result');
      
      return result;
    } catch (e) {
      print('getWalletNonce error: $e');
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
      print('=== OROCASH READ ===');
      print('URL: $url');
      print('Method: $method');
      print('Params: $params');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: json.encode({
          'method': method,
          if (params != null) 'params': params,
        }),
      );
      final result = _parseResponse(response);
      
      print('Status: ${response.statusCode}');
      print('Response: $result');
      
      return result;
    } catch (e) {
      print('oroCashRead error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
  
  @override
  Future<Map<String, dynamic>> adminMint(
      String toAddress, String amount, Map<String, String> headers) async {
    try {
      print('\n=== ADMIN MINT ===');
      final url = '$baseUrl/admin/mint';
      print('URL: $url');
      print('address: $toAddress');
      print('amount: $amount');
      print('Headers: $headers');
      
      final requestBody = {
        'address': toAddress,
        'amount': amount,
      };
      print('Request body: $requestBody');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      print('Status: ${response.statusCode}');
      print('Response: ${response.body}');
      return _parseResponse(response);
    } catch (e) {
      print('Error in adminMint: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  @override
  Future<Map<String, dynamic>> adminWhitelist(
      String walletAddress, Map<String, String> headers) async {
    try {
      print('\n=== ADMIN WHITELIST ===');
      final url = '$baseUrl/admin/whitelist';
      print('URL: $url');
      print('walletAddress: $walletAddress');
      print('Headers: $headers');
      
      final requestBody = {
        'address': walletAddress,
      };
      print('Request body: $requestBody');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      print('Status: ${response.statusCode}');
      print('Response: ${response.body}');
      return _parseResponse(response);
    } catch (e) {
      print('Error in adminWhitelist: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  @override
  Future<Map<String, dynamic>> getContracts() async {
    try {
      final url = '$baseUrl/contracts';
      print('=== GET CONTRACTS ===');
      print('URL: $url');
      
      final response = await http.get(Uri.parse(url));
      final result = _parseResponse(response);
      
      print('Status: ${response.statusCode}');
      print('Response: $result');
      
      return result;
    } catch (e) {
      print('getContracts error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  @override
    Future<Map<String, dynamic>> getGoldPrice(Map<String, String> headers) async {
    try {
      final url = '$baseUrl/gold/price';
      print('=== GET GOLD PRICE ===');
      print('URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {...headers, 'Content-Type': 'application/json'},
      );
      final result = _parseResponse(response);
      
      print('Status: ${response.statusCode}');
      print('Response: $result');
      
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
      print('getGoldPrice error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
