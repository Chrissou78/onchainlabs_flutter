import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

/// Captured verbatim from ga-api-dev.onchainlabs.ch/random on 2026-09-05.
/// Kept byte-exact: if the server's format drifts, this test should fail and
/// tell us, rather than the SDK silently rejecting every login in production.
const _devChallenge = '''
ga-dev.onchainlabs.ch wants you to sign in with your Ethereum account:
0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045

Sign in to the Gold Avenue API. This signature only authenticates you: it does not authorize any transaction, transfer or other on-chain action.

URI: https://ga-dev.onchainlabs.ch
Version: 1
Chain ID: 80002
Nonce: aa99a8442c1d31ea0385f6a412222c6a
Issued At: 2026-09-05T18:42:28.346Z
Expiration Time: 2026-09-05T22:42:28.346Z''';

const _address = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';

/// Inside the challenge's validity window.
final _duringWindow = DateTime.utc(2026, 9, 5, 19, 0, 0);

void main() {
  _headerEncodingTests();

  group('parse', () {
    test('accepts the real server challenge and reads every field', () {
      final c = SiweChallenge.parse(_devChallenge);

      expect(c.domain, 'ga-dev.onchainlabs.ch');
      expect(c.address, _address);
      expect(c.uri, 'https://ga-dev.onchainlabs.ch');
      expect(c.chainId, 80002);
      expect(c.nonce, 'aa99a8442c1d31ea0385f6a412222c6a');
      expect(c.issuedAt, DateTime.utc(2026, 9, 5, 18, 42, 28, 346));
      expect(c.expirationTime, DateTime.utc(2026, 9, 5, 22, 42, 28, 346));
    });

    // This is the X-01 case: the whole point of the guard.
    test('rejects a 32-byte transaction digest', () {
      final digest = '0x${'ab' * 32}';
      expect(
        () => SiweChallenge.parse(digest),
        throwsA(isA<ChallengeRejected>()),
      );
    });

    test('rejects bare hex with no 0x prefix', () {
      expect(
        () => SiweChallenge.parse('cd' * 32),
        throwsA(isA<ChallengeRejected>()),
      );
    });

    test('rejects an empty challenge', () {
      expect(() => SiweChallenge.parse('   '),
          throwsA(isA<ChallengeRejected>()));
    });

    test('rejects arbitrary prose that is not a sign-in message', () {
      expect(
        () => SiweChallenge.parse('please sign this to continue'),
        throwsA(isA<ChallengeRejected>()),
      );
    });

    test('rejects a challenge with no nonce', () {
      final noNonce = _devChallenge
          .split('\n')
          .where((l) => !l.startsWith('Nonce:'))
          .join('\n');
      expect(() => SiweChallenge.parse(noNonce),
          throwsA(isA<ChallengeRejected>()));
    });
  });

  group('validate', () {
    test('passes for the right wallet, chain and time', () {
      final c = SiweChallenge.validate(
        _devChallenge,
        expectedAddress: _address,
        expectedChainId: 80002,
        now: _duringWindow,
      );
      expect(c.nonce, isNotEmpty);
    });

    test('address comparison is case-insensitive', () {
      expect(
        () => SiweChallenge.validate(
          _devChallenge,
          expectedAddress: _address.toLowerCase(),
          now: _duringWindow,
        ),
        returnsNormally,
      );
    });

    test('rejects a challenge addressed to another wallet', () {
      expect(
        () => SiweChallenge.validate(
          _devChallenge,
          expectedAddress: '0x0000000000000000000000000000000000000001',
          now: _duringWindow,
        ),
        throwsA(isA<ChallengeRejected>()),
      );
    });

    test('rejects a challenge bound to a different chain', () {
      expect(
        () => SiweChallenge.validate(
          _devChallenge,
          expectedAddress: _address,
          expectedChainId: 137, // polygon mainnet; challenge says 80002
          now: _duringWindow,
        ),
        throwsA(isA<ChallengeRejected>()),
      );
    });

    test('rejects an expired challenge', () {
      expect(
        () => SiweChallenge.validate(
          _devChallenge,
          expectedAddress: _address,
          now: DateTime.utc(2026, 9, 6), // well past Expiration Time
        ),
        throwsA(isA<ChallengeRejected>()),
      );
    });

    test('rejects a challenge issued in the future', () {
      expect(
        () => SiweChallenge.validate(
          _devChallenge,
          expectedAddress: _address,
          now: DateTime.utc(2026, 9, 4), // before Issued At
        ),
        throwsA(isA<ChallengeRejected>()),
      );
    });

    // Guards the deliberate default: dev's SIWE domain (ga-dev) differs from
    // the host the SDK calls (ga-api-dev), so enforcing domain binding
    // unconditionally would fail every login there.
    test('ignores a domain mismatch when no domain is expected', () {
      expect(
        () => SiweChallenge.validate(
          _devChallenge,
          expectedAddress: _address,
          now: _duringWindow,
        ),
        returnsNormally,
      );
    });

    test('rejects a domain mismatch once a domain is expected', () {
      expect(
        () => SiweChallenge.validate(
          _devChallenge,
          expectedAddress: _address,
          expectedDomain: 'ga-api-dev.onchainlabs.ch',
          now: _duringWindow,
        ),
        throwsA(isA<ChallengeRejected>()),
      );
    });

    test('accepts the domain it actually declares', () {
      expect(
        () => SiweChallenge.validate(
          _devChallenge,
          expectedAddress: _address,
          expectedDomain: 'ga-dev.onchainlabs.ch',
          now: _duringWindow,
        ),
        returnsNormally,
      );
    });
  });
}

/// The transport bug: an EIP-4361 challenge is multi-line, and dart:io rejects
/// a header value containing CR/LF before the request is sent. Every
/// authenticated call in 4.3.0–4.6.0 therefore threw FormatException.
void _headerEncodingTests() {
  group('encodeChallengeForHeader', () {
    test('a real multi-line challenge becomes header-safe', () {
      final encoded = encodeChallengeForHeader(_devChallenge);
      expect(encoded, isNot(contains('\n')));
      expect(encoded, isNot(contains('\r')));
    });

    test('round-trips to the exact bytes the signature covers', () {
      final encoded = encodeChallengeForHeader(_devChallenge);
      expect(utf8.decode(base64.decode(encoded)), _devChallenge);
    });

    test('a single-line challenge is passed through untouched', () {
      const plain = 'some-opaque-single-line-challenge';
      expect(encodeChallengeForHeader(plain), plain);
    });

    test('output is valid in an HTTP header value', () {
      // RFC 7230: visible ASCII, plus space and horizontal tab. Base64 output
      // is a strict subset, so this holds by construction — assert it anyway,
      // because this is the property the whole fix rests on.
      final encoded = encodeChallengeForHeader(_devChallenge);
      expect(RegExp(r'^[\x21-\x7E]+$').hasMatch(encoded), isTrue);
    });
  });
}
