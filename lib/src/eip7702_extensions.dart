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
  ///
  /// Both addresses are validated before encoding. `padLeft` lengthens short
  /// input but does not truncate long input, so an over-length or non-hex
  /// address would shift the amount field and encode a different transfer
  /// than the caller asked for.
  BatchCallBuilder addTransfer({
    required String contractAddress,
    required String to,
    required BigInt amount,
  }) {
    if (amount.isNegative) {
      throw ArgumentError.value(
        amount,
        'amount',
        'transfer amount cannot be negative',
      );
    }

    const selector = 'a9059cbb';
    final toAddress =
        Eip7702Executor.requireAddressHex(to, 'to').padLeft(64, '0');
    final amountHex = amount.toRadixString(16).padLeft(64, '0');
    final data = '0x$selector$toAddress$amountHex';

    // Validate only — do not normalise. This value is forwarded to the API in
    // the calls array as given, so stripping its 0x prefix here would change
    // what the server receives.
    Eip7702Executor.requireAddressHex(contractAddress, 'contractAddress');

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
