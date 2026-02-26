// lib/src/eip7702_extensions.dart

import 'dart:typed_data';
import 'eip7702_executor.dart';

/// Builder for batch calls
class BatchCallBuilder {
  final List<BatchCall> _calls = [];

  /// Add a call to the batch
  BatchCallBuilder addCall({
    required String to,
    required String data,
    BigInt? value,
  }) {
    _calls.add(BatchCall(to: to, data: data, value: value));
    return this;
  }

  /// Add a transfer call
  BatchCallBuilder addTransfer({
    required String contractAddress,
    required String to,
    required BigInt amount,
  }) {
    final selector = 'a9059cbb';
    final toAddress = to.replaceFirst('0x', '').padLeft(64, '0');
    final amountHex = amount.toRadixString(16).padLeft(64, '0');
    final data = '0x$selector$toAddress$amountHex';
    
    return addCall(to: contractAddress, data: data);
  }

  /// Get the calls
  List<BatchCall> build() => List.unmodifiable(_calls);
}

/// Extension methods for batch execution
extension BatchExecutorExtension on Eip7702Executor {
  /// Execute a batch of calls using a builder
  Future<Eip7702Result> executeBatch(
    Uint8List privateKeyBytes,
    BatchCallBuilder builder, {
    bool waitForTx = false,
  }) {
    return executeBatchGasless(
      privateKeyBytes,
      builder.build(),
      waitForTx: waitForTx,
    );
  }
}
