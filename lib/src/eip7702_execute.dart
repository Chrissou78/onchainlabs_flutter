import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart'; // for ContractAbi, ContractFunction
import 'package:hex/hex.dart';
import 'package:pointycastle/digests/keccak.dart';

import 'api.dart';
import 'models.dart';

/// Simple nonce response matching the TS SDK.
class NonceResponse {
  final BigInt nonce;
  final BigInt delegationNonce;

  NonceResponse({
    required this.nonce,
    required this.delegationNonce,
  });
}

/// One gasless call (one contract method).
class GaslessTransaction {
  final String contractAddress;
  final String method;
  final List<dynamic> params;

  const GaslessTransaction({
    required this.contractAddress,
    required this.method,
    required this.params,
  });
}

class Eip7702Executor {
  final PolygonWalletApi api;

  Eip7702Executor({required this.api});

  /// Generate x-message / x-signature headers, like TS generateAuthHeaders.
  Future<Map<String, String>> generateAuthHeaders(
      EthPrivateKey signer) async {
    final addrRaw = signer.address.toString();
    final addr = addrRaw.startsWith('0x') ? addrRaw : '0x$addrRaw';

    final randomMessage = await api.getRandomMessage(addr);

    final payload = Uint8List.fromList(utf8.encode(randomMessage));
    final sigBytes = signer.signPersonalMessageToUint8List(payload);
    final signature = '0x${HEX.encode(sigBytes)}';

    return {
      'x-message': randomMessage,
      'x-signature': signature,
    };
  }

  /// Get nonce + delegationNonce as in TS getNonce().
  Future<NonceResponse> getNonce(EthPrivateKey signer) async {
    final headers = await generateAuthHeaders(signer);
    final raw = await api.getNonces(headers);

    final nonceRaw = raw['nonce'];
    final delegationNonceRaw = raw['delegationNonce'];

    if (nonceRaw == null || delegationNonceRaw == null) {
      throw Exception('Invalid nonce response: $raw');
    }

    final nonce = BigInt.parse(nonceRaw.toString());
    final delegationNonce = BigInt.parse(delegationNonceRaw.toString());

    return NonceResponse(
      nonce: nonce,
      delegationNonce: delegationNonce,
    );
  }

  /// Check delegation status. Does NOT call wallet.authorize here.
  Future<void> ensureDelegated(EthPrivateKey signer) async {
    final headers = await generateAuthHeaders(signer);
    final status = await api.status(headers);

    final delegated = status['delegated'] == true;
    if (!delegated) {
      throw Exception(
        'Admin wallet is not delegated. '
        'Run authorize() via your TS SDK or backend first.',
      );
    }
  }

  /// Generic execute() equivalent from TS.
  ///
  /// - fetch ABI per contractAddress via api.getContractABI()
  /// - encode calls (to, 0, data)
  /// - encodedCalls = concat( pack(["address","uint256","bytes"], [to,value,data]) )
  /// - digest = keccak256( pack(["uint256","bytes"], [delegationNonce, encodedCalls]) )
  /// - signature = personal_sign(digestBytes)
  /// - api.sponsor(calls, signature, waitForTx, headers)
  Future<Map<String, dynamic>> executeGasless({
    required EthPrivateKey signer,
    required List<GaslessTransaction> transactions,
    bool waitForTx = false,
  }) async {
    if (transactions.isEmpty) {
      throw Exception('No transactions to execute');
    }

    // Make sure this signer is already delegated.
    await ensureDelegated(signer);

    // Fetch and cache ABIs per contract.
    final Map<String, dynamic> abiCache = {};
    final List<List<dynamic>> calls = [];

    for (final tx in transactions) {
      if (!abiCache.containsKey(tx.contractAddress)) {
        final abiRaw = await api.getContractABI(tx.contractAddress);
        final abiJsonString =
            abiRaw is String ? abiRaw : jsonEncode(abiRaw);
        abiCache[tx.contractAddress] = abiJsonString;
      }

      final abiString = abiCache[tx.contractAddress] as String;

      final contractAbi = ContractAbi.fromJson(abiString, 'Contract');

      // Get function by name from the ABI (no DeployedContract needed).
      final fn = contractAbi.functions
          .firstWhere((f) => f.name == tx.method, orElse: () {
        throw Exception(
          'Function ${tx.method} not found in ABI for ${tx.contractAddress}',
        );
      });

      final dataBytes = fn.encodeCall(tx.params);
      calls.add([
        tx.contractAddress,
        BigInt.zero,
        dataBytes,
      ]);
    }

    // encodedCalls = "0x" + concat( pack(["address","uint256","bytes"], [to,value,data]) )
    var encodedCallsHex = '0x';
    for (final call in calls) {
      final to = call[0] as String;
      final value = call[1] as BigInt;
      final dataBytes = call[2] as Uint8List;

      final packed = _packAddressUintBytes(to, value, dataBytes);
      encodedCallsHex += _bytesToHex(packed, include0x: false);
    }

    // Get nonces (we need delegationNonce)
    final nonces = await getNonce(signer);

    // digest = keccak256( pack(["uint256","bytes"], [delegationNonce, encodedCalls]) )
    final digestBytes = _buildDigestBytes(
      nonces.delegationNonce,
      encodedCallsHex,
    );

    // TS: wallet.signMessage(getBytes(digest))
    final sigBytes =
        signer.signPersonalMessageToUint8List(digestBytes);
    final signature = '0x${HEX.encode(sigBytes)}';

    // Auth headers for sponsor call
    final headers = await generateAuthHeaders(signer);

    // Prepare calls payload: convert BigInt and bytes to strings
    final callsPayload = calls
        .map((call) => [
              call[0], // contractAddress string
              (call[1] as BigInt).toString(),
              '0x${_bytesToHex(call[2] as Uint8List, include0x: false)}',
            ])
        .toList();

    // Backend expects `calls` as JSON string (stringify(calls) in TS).
    final tx = await api.sponsor(
      callsPayload,
      signature,
      waitForTx,
      headers,
    );

    return tx;
  }

  /// Gasless mint, wrapped in execute().
  ///
  /// Mint ABI:
  /// function MintToken(address Receiver, uint256 Amount)
  Future<Map<String, dynamic>> executeMintGasless({
    required EthPrivateKey adminSigner,
    required PolygonWallet destination,
    required String amountBaseUnits, // already 6-decimal base units
    bool waitForTx = false,
    required String mintContractAddress, // MintToken contract address
  }) async {
    const String mintMethodName = 'MintToken';

    final tx = GaslessTransaction(
      contractAddress: mintContractAddress,
      method: mintMethodName,
      params: [
        destination.address,              // Receiver
        BigInt.parse(amountBaseUnits),    // Amount
      ],
    );

    return executeGasless(
      signer: adminSigner,
      transactions: [tx],
      waitForTx: waitForTx,
    );
  }

  // ---- internal helpers ----

  Uint8List _packAddressUintBytes(
    String address,
    BigInt value,
    Uint8List data,
  ) {
    final addrBytes = _hexToBytes(
      address.startsWith('0x') ? address : '0x$address',
    );

    if (addrBytes.length != 20) {
      throw Exception(
        'Address must be 20 bytes. Got: ${addrBytes.length}',
      );
    }

    final valueBytes = _uint256ToBytes(value);

    final out = Uint8List(
      addrBytes.length + valueBytes.length + data.length,
    );
    var offset = 0;

    out.setRange(offset, offset + addrBytes.length, addrBytes);
    offset += addrBytes.length;

    out.setRange(offset, offset + valueBytes.length, valueBytes);
    offset += valueBytes.length;

    out.setRange(offset, offset + data.length, data);

    return out;
  }

  Uint8List _uint256ToBytes(BigInt value) {
    if (value.isNegative) {
      throw Exception('uint256 cannot be negative');
    }

    var v = value;
    final bytes = Uint8List(32);
    for (int i = 31; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return bytes;
  }

  Uint8List _buildDigestBytes(
    BigInt delegationNonce,
    String encodedCallsHex,
  ) {
    final nonceBytes = _uint256ToBytes(delegationNonce);
    final callsBytes = _hexToBytes(
      encodedCallsHex.startsWith('0x')
          ? encodedCallsHex
          : '0x$encodedCallsHex',
    );

    final combined = Uint8List(nonceBytes.length + callsBytes.length);
    combined.setRange(0, nonceBytes.length, nonceBytes);
    combined.setRange(
      nonceBytes.length,
      combined.length,
      callsBytes,
    );

    final digest = _keccak256(combined);
    return Uint8List.fromList(digest);
  }

  // ---- pure hex / keccak helpers (no web3dart.crypto) ----

  Uint8List _hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.length % 2 != 0) {
      throw Exception('Invalid hex length');
    }
    final result = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < clean.length; i += 2) {
      final byteStr = clean.substring(i, i + 2);
      result[i ~/ 2] = int.parse(byteStr, radix: 16);
    }
    return result;
  }

  String _bytesToHex(Uint8List bytes, {bool include0x = false}) {
    final hexStr = HEX.encode(bytes);
    return include0x ? '0x$hexStr' : hexStr;
  }

  /// Keccak-256 using pointycastle.
  Uint8List _keccak256(Uint8List input) {
    final d = KeccakDigest(256);
    d.reset();
    d.update(input, 0, input.length);
    final out = Uint8List(d.digestSize);
    d.doFinal(out, 0);
    return out;
  }
}
