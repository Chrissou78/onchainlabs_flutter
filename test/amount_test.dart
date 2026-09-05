import 'package:flutter_test/flutter_test.dart';
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

/// X-07: monetary amounts must not pass through IEEE-754 doubles on their way
/// to a signature. These vectors pin the exact-arithmetic path.
BigInt parse(String amount, {int decimals = 6}) =>
    Eip7702Executor.parseAmountWithDecimals(amount, decimals);

void main() {
  group('parseAmountWithDecimals', () {
    test('whole numbers', () {
      expect(parse('0'), BigInt.zero);
      expect(parse('1'), BigInt.from(1000000));
      expect(parse('12'), BigInt.from(12000000));
    });

    test('decimal fractions are exact', () {
      expect(parse('0.1'), BigInt.from(100000));
      expect(parse('0.000001'), BigInt.one);
      expect(parse('1.5'), BigInt.from(1500000));
      expect(parse('12.345678'), BigInt.from(12345678));
    });

    test('short fractions are right-padded, not left-padded', () {
      expect(parse('0.5'), BigInt.from(500000));
      expect(parse('0.05'), BigInt.from(50000));
      expect(parse('0.000010'), BigInt.from(10));
    });

    test('leading and omitted zeros', () {
      expect(parse('.5'), BigInt.from(500000));
      expect(parse('007'), BigInt.from(7000000));
      expect(parse('  1.25  '), BigInt.from(1250000));
    });

    test('negatives', () {
      expect(parse('-1.5'), BigInt.from(-1500000));
      expect(parse('-0.000001'), -BigInt.one);
    });

    // The reason string arithmetic matters: these exceed a double's exact
    // integer range (~9e15 base units), where the old multiply-and-round
    // could not represent the value at all.
    test('values beyond double precision stay exact', () {
      expect(parse('10000000000.000001'), BigInt.parse('10000000000000001'));
      expect(
        parse('123456789012345.678901'),
        BigInt.parse('123456789012345678901'),
      );
    });

    test('honours a different token precision', () {
      expect(parse('1.5', decimals: 18), BigInt.parse('1500000000000000000'));
      expect(parse('1.5', decimals: 2), BigInt.from(150));
      expect(parse('1', decimals: 0), BigInt.one);
    });

    test('rejects more precision than the token has', () {
      // Truncating a user's amount silently is worse than refusing it.
      expect(() => parse('0.0000001'), throwsFormatException);
      expect(() => parse('1.123', decimals: 2), throwsFormatException);
    });

    test('rejects malformed input', () {
      expect(() => parse(''), throwsFormatException);
      expect(() => parse('   '), throwsFormatException);
      expect(() => parse('abc'), throwsFormatException);
      expect(() => parse('1.2.3'), throwsFormatException);
      expect(() => parse('1,5'), throwsFormatException);
      expect(() => parse('1.2e3'), throwsFormatException);
    });
  });
}
