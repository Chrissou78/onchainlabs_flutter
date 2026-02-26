// lib/src/orocash_contract.dart

import 'dart:typed_data';
import 'eip7702_executor.dart';

/// Helper class for OroCash contract interactions
class OroCashContract {
  final Eip7702Executor _executor;
  final String contractAddress;

  OroCashContract({
    required Eip7702Executor executor,
    required this.contractAddress,
  }) : _executor = executor;

  /// Get balance
  Future<BigInt> balance(Uint8List privateKeyBytes, String address) async {
    return _executor.getOroCashBalanceWithSignature(privateKeyBytes, address);
  }

  /// Get balance formatted
  Future<double> balanceFormatted(
    Uint8List privateKeyBytes,
    String address, {
    int decimals = 6,
  }) async {
    final bal = await balance(privateKeyBytes, address);
    return bal / BigInt.from(10).pow(decimals);
  }

  /// Get total supply
  Future<BigInt> totalSupply(Uint8List privateKeyBytes) async {
    return _executor.getOroCashTotalSupplyWithSignature(privateKeyBytes);
  }

  /// Get name
  Future<String> name(Uint8List privateKeyBytes) async {
    return _executor.getOroCashNameWithSignature(privateKeyBytes);
  }

  /// Get symbol
  Future<String> symbol(Uint8List privateKeyBytes) async {
    return _executor.getOroCashSymbolWithSignature(privateKeyBytes);
  }

  /// Get decimals
  Future<int> decimals(Uint8List privateKeyBytes) async {
    return _executor.getOroCashDecimalsWithSignature(privateKeyBytes);
  }

  /// Transfer tokens
  Future<Eip7702Result> transfer(
    Uint8List privateKeyBytes,
    String to,
    BigInt amount, {
    bool waitForTx = false,
  }) async {
    return _executor.transferOroCash(
      privateKeyBytes,
      contractAddress,
      to,
      amount,
      waitForTx: waitForTx,
    );
  }

  /// Transfer tokens with formatted amount
  Future<Eip7702Result> transferFormatted(
    Uint8List privateKeyBytes,
    String to,
    double amount, {
    int decimals = 6,
    bool waitForTx = false,
  }) async {
    return _executor.transferOroCashFormatted(
      privateKeyBytes,
      contractAddress,
      to,
      amount,
      waitForTx: waitForTx,
    );
  }
}
