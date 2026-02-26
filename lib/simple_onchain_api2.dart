// lib/simple_onchain_api.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/digests/keccak.dart';

import 'src/models.dart'; // PolygonWallet / WalletManager types (your package structure)

class SimpleOnchainApi {
  final String baseUrl;
  final String publicKey;

  SimpleOnchainApi({
    required this.publicKey,
    this.baseUrl = 'https://dev-ga-api.onchainlabs.ch',
  });

  Exception _err(String path, http.Response resp) {
    return Exception(
      'Request to $path failed (status: ${resp.statusCode}, body: ${resp.body})',
    );
  }

  Future<Map<String, dynamic>> _json(http.Response r, String path) async {
    if (r.statusCode < 200 || r.statusCode >= 300) throw _err(path, r);
    if (r.body.isEmpty) return {};
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ------------------------
  // backend /random helper + signing helpers
  // ------------------------

  Future<String> _getRandom(String address) async {
    final uri = Uri.parse('$baseUrl/random');
    final r = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': publicKey,
      },
      body: jsonEncode({'address': address}),
    );
    final j = await _json(r, '/random');
    if (!j.containsKey('signMessage')) throw Exception('No signMessage in /random response');
    return j['signMessage'] as String;
  }

  Future<String> _signPersonal(EthPrivateKey key, String message) async {
    final payload = Uint8List.fromList(utf8.encode(message));
    final sig = await key.signPersonalMessageToUint8List(payload);
    return '0x${HEX.encode(sig)}';
  }

  Future<Map<String, String>> _authHeaders(PolygonWallet w) async {
    final challenge = await _getRandom(w.address);
    final creds = EthPrivateKey.fromHex(w.privateKeyHex);
    final signature = await _signPersonal(creds, challenge);

    return {
      'Content-Type': 'application/json',
      'x-api-key': publicKey,
      'x-message': challenge,
      'x-signature': signature,
    };
  }

  // ------------------------
  // nonce retrieval
  // ------------------------

  Future<Map<String, dynamic>> _getNonces(Map<String, String> headers) async {
    final uri = Uri.parse('$baseUrl/nonce');
    final r = await http.get(uri, headers: headers);
    return _json(r, '/nonce');
  }

  // ------------------------
  // Build "deterministic" signature payload for execute
  // Notes:
  // - Backend contract-side expects a specific struct hash; we approximate by
  //   hashing the JSON-encoded function + args then signing that plus nonce/deadline.
  // - This matches the backend's expectation for "signed intent" used by execute.
  // ------------------------

  Uint8List _keccak(Uint8List data) {
    final digest = KeccakDigest(256);
    return digest.process(data);
  }

  /// Build deterministic message to sign for execute.
  /// Content: keccak( contractAddress || functionName || keccak(jsonArgs) || nonce || deadline )
  Uint8List _buildExecuteMessageBytes({
    required String contractAddress,
    required String functionName,
    required Map<String, dynamic> args,
    required int nonce,
    required int deadline,
  }) {
    final contractNormalized = contractAddress.toLowerCase(); // string form
    final fnBytes = utf8.encode(functionName);
    final argsJson = jsonEncode(args);
    final argsHash = _keccak(Uint8List.fromList(utf8.encode(argsJson)));
    final nonceBytes = _u64ToBytes(nonce);
    final deadlineBytes = _u64ToBytes(deadline);

    final joined = BytesBuilder();
    joined.add(utf8.encode(contractNormalized));
    joined.add(fnBytes);
    joined.add(argsHash);
    joined.add(nonceBytes);
    joined.add(deadlineBytes);

    final total = joined.toBytes();
    final finalHash = _keccak(total); // 32 bytes
    return finalHash;
  }

  Uint8List _u64ToBytes(int v) {
    final b = Uint8List(32);
    // big-endian into last bytes
    for (var i = 0; i < 32; i++) {
      final shift = (31 - i) * 8;
      if (shift >= 64) {
        b[i] = 0;
      } else {
        b[i] = ((v >> (shift)) & 0xff);
      }
    }
    return b;
  }

  Future<Map<String, dynamic>> _postExecute({
    required PolygonWallet signerWallet,
    required String contractAddress,
    required String func,
    required Map<String, dynamic> args,
    bool waitForTx = true,
  }) async {
    // 1) build auth headers (x-message/x-signature) for signer
    final authHeaders = await _authHeaders(signerWallet);

    // 2) get nonces
    final nonces = await _getNonces(authHeaders);
    // prefer delegationNonce if present, fallback to nonce
    final delegationNonce = nonces['delegationNonce'] ?? nonces['nonce'] ?? 0;
    final nonce = (delegationNonce is int) ? delegationNonce : int.parse(delegationNonce.toString());

    // 3) build deadline (unix), 1 hour from now
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final deadline = now + 3600;

    // 4) build struct hash and sign it with wallet private key (personal_sign)
    final digest = _buildExecuteMessageBytes(
      contractAddress: contractAddress,
      functionName: func,
      args: args,
      nonce: nonce,
      deadline: deadline,
    );

    // sign digest as personal message
    final creds = EthPrivateKey.fromHex(signerWallet.privateKeyHex);
    final signature = await _signPersonal(creds, '0x${HEX.encode(digest)}');

    // 5) POST to /execute
    final uri = Uri.parse('$baseUrl/execute');
    final body = {
      'function': func,
      'args': args,
      'nonce': nonce,
      'deadline': deadline,
      'signature': signature,
      'waitForTx': waitForTx,
      'contractAddress': contractAddress,
    };

    final headers = Map<String, String>.from(authHeaders);
    headers['Content-Type'] = 'application/json';

    final r = await http.post(uri, headers: headers, body: jsonEncode(body));
    return _json(r, '/execute');
  }

  // ------------------------
  // amount conversion (6 decimals)
  // ------------------------

  String _toBaseUnits6(String human) {
    final parts = human.split('.');
    final whole = parts[0].isEmpty ? '0' : parts[0];
    final frac = parts.length == 2 ? parts[1] : '';
    if (frac.length > 6) throw Exception('Max 6 decimals allowed');
    if (!RegExp(r'^[0-9]+$').hasMatch(whole)) throw Exception('Invalid whole part');
    if (frac.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(frac)) throw Exception('Invalid fraction part');
    final out = whole + frac.padRight(6, '0');
    final trimmed = out.replaceFirst(RegExp(r'^0+'), '');
    return trimmed.isEmpty ? '0' : trimmed;
  }

  // ------------------------
  // Public balance (GET /balance/{address}) — doesn't use execute
  // ------------------------

  Future<Map<String, dynamic>> balanceOfPublic(String address) async {
    final uri = Uri.parse('$baseUrl/balance/$address');
    final r = await http.get(uri, headers: {
      'accept': 'application/json',
      'x-api-key': publicKey,
    });
    return _json(r, '/balance');
  }

  // ------------------------
  // Execute wrappers (require contractAddress parameter)
  // ------------------------

  Future<Map<String, dynamic>> mint({
    required PolygonWallet signerWallet,
    required String contractAddress,
    required String receiver,
    required String amountHuman,
    bool waitForTx = true,
  }) {
    return _postExecute(
      signerWallet: signerWallet,
      contractAddress: contractAddress,
      func: 'MintToken',
      args: {
        'Receiver': receiver,
        'Amount': _toBaseUnits6(amountHuman),
      },
      waitForTx: waitForTx,
    );
  }

  Future<Map<String, dynamic>> checkAccount({
    required PolygonWallet signerWallet,
    required String contractAddress,
    required String account,
  }) {
    return _postExecute(
      signerWallet: signerWallet,
      contractAddress: contractAddress,
      func: 'CheckAccount',
      args: {'account': account},
      waitForTx: false,
    );
  }

  Future<Map<String, dynamic>> buyToken({
    required PolygonWallet signerWallet,
    required String contractAddress,
    required String from,
    required String to,
    required String amountHuman,
    bool waitForTx = true,
  }) {
    return _postExecute(
      signerWallet: signerWallet,
      contractAddress: contractAddress,
      func: 'Buytoken',
      args: {
        'from': from,
        'to': to,
        'value': _toBaseUnits6(amountHuman),
      },
      waitForTx: waitForTx,
    );
  }

  Future<Map<String, dynamic>> sellToken({
    required PolygonWallet signerWallet,
    required String contractAddress,
    required String from,
    required String to,
    required String amountHuman,
    bool waitForTx = true,
  }) {
    return _postExecute(
      signerWallet: signerWallet,
      contractAddress: contractAddress,
      func: 'SellToken',
      args: {
        'from': from,
        'to': to,
        'value': _toBaseUnits6(amountHuman),
      },
      waitForTx: waitForTx,
    );
  }

  Future<Map<String, dynamic>> transfer({
    required PolygonWallet signerWallet,
    required String contractAddress,
    required String to,
    required String amountHuman,
    bool waitForTx = true,
  }) {
    return _postExecute(
      signerWallet: signerWallet,
      contractAddress: contractAddress,
      func: 'transfer',
      args: {
        'to': to,
        'value': _toBaseUnits6(amountHuman),
      },
      waitForTx: waitForTx,
    );
  }

  Future<Map<String, dynamic>> transferFrom({
    required PolygonWallet signerWallet,
    required String contractAddress,
    required String from,
    required String to,
    required String amountHuman,
    bool waitForTx = true,
  }) {
    return _postExecute(
      signerWallet: signerWallet,
      contractAddress: contractAddress,
      func: 'transferFrom',
      args: {
        'from': from,
        'to': to,
        'value': _toBaseUnits6(amountHuman),
      },
      waitForTx: waitForTx,
    );
  }

  Future<Map<String, dynamic>> approve({
    required PolygonWallet signerWallet,
    required String contractAddress,
    required String spender,
    required String amountHuman,
    bool waitForTx = true,
  }) {
    return _postExecute(
      signerWallet: signerWallet,
      contractAddress: contractAddress,
      func: 'approve',
      args: {
        'spender': spender,
        'value': _toBaseUnits6(amountHuman),
      },
      waitForTx: waitForTx,
    );
  }
}
