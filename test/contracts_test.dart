import 'package:flutter_test/flutter_test.dart';
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

/// T-06: contract addresses are release constants, not runtime configuration.
///
/// These values were verified on-chain on 6 September 2026 with eth_getCode:
/// each carries contract code on its own chain and none on the other. If a
/// deployment ever moves, this test is the place that has to change, and a
/// mismatch here should stop a release rather than surface at signing time.
void main() {
  group('kOnchainLabsContracts', () {
    test('covers both supported chains', () {
      expect(kOnchainLabsContracts.keys.toSet(), {137, 80002});
    });

    test('polygon mainnet addresses are pinned', () {
      final c = kOnchainLabsContracts[137]!;
      expect(c.delegate, '0x11a2C6C6368376Dd97d2D8Ad45eff904E4186BDD');
      expect(c.token, '0x4CD6FFD022F3d777425F1f3BBf4DeD66d3eD1Fad');
    });

    test('amoy testnet addresses are pinned', () {
      final c = kOnchainLabsContracts[80002]!;
      expect(c.delegate, '0xAC5d44B5d38e8E3541D79B005AcC2E8965A2b291');
      expect(c.token, '0xcc7fA40292D7CaD12C2033d613ce483C1A89a8A2');
    });

    test('every address is a well-formed 20-byte hex address', () {
      for (final entry in kOnchainLabsContracts.entries) {
        for (final a in [entry.value.delegate, entry.value.token]) {
          expect(
            () => Eip7702Executor.requireAddressHex(a, 'address'),
            returnsNormally,
            reason: 'chain ${entry.key}: $a',
          );
        }
      }
    });

    // The mainnet and testnet pairs must never be confused for one another:
    // signing a delegation to the wrong chain's contract is the failure this
    // whole finding is about.
    test('no address is shared between chains', () {
      final mainnet = kOnchainLabsContracts[137]!;
      final amoy = kOnchainLabsContracts[80002]!;
      expect(mainnet.delegate, isNot(amoy.delegate));
      expect(mainnet.token, isNot(amoy.token));
    });

    test('delegate and token are distinct within a chain', () {
      for (final c in kOnchainLabsContracts.values) {
        expect(c.delegate.toLowerCase(), isNot(c.token.toLowerCase()));
      }
    });

    // The v3.2.0 fallback assigned the gas-paying sponsor EOA to the delegate
    // slot (audit T-11). It has no contract code on either chain, so a
    // delegation to it would brick the account. It must never reappear here.
    test('the v3.2.0 paymaster EOA is not present', () {
      const paymaster = '0xa7de21f5fc304f2d9e012b7faaa786621173d61c';
      for (final c in kOnchainLabsContracts.values) {
        expect(c.delegate.toLowerCase(), isNot(paymaster));
        expect(c.token.toLowerCase(), isNot(paymaster));
      }
    });
  });
}
