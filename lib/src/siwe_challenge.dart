// lib/src/siwe_challenge.dart

import 'dart:convert';

/// Thrown when a server-supplied authentication challenge is not something
/// this SDK is willing to sign.
class ChallengeRejected implements Exception {
  final String reason;
  const ChallengeRejected(this.reason);

  @override
  String toString() => 'ChallengeRejected: $reason';
}

/// Encode a sign-in challenge for transport in an HTTP header.
///
/// An HTTP header value cannot contain CR or LF (RFC 7230 §3.2), and an
/// EIP-4361 challenge is multi-line by construction — domain, address,
/// statement, URI, version, chain id, nonce and timestamps each on their own
/// line. Putting the raw message in `x-message` therefore does not merely risk
/// a malformed request: `dart:io` rejects it before the request leaves the
/// process, so every authenticated call throws
/// `FormatException: Invalid HTTP header field value`.
///
/// The API accepts a base64-encoded `x-message` and verifies the signature
/// against the decoded bytes. Confirmed against ga-api-dev on 7 September 2026:
/// a base64 challenge authenticates, while a wrong signer, a nonce the server
/// never issued, and a non-SIWE payload are each still rejected with 401 — so
/// the server is decoding and verifying, not ignoring the header.
///
/// A challenge with no line breaks is returned unchanged, so any deployment
/// still issuing single-line challenges behaves exactly as before.
String encodeChallengeForHeader(String message) {
  if (!message.contains('\n') && !message.contains('\r')) return message;
  return base64.encode(utf8.encode(message));
}

/// A parsed EIP-4361 (Sign-In with Ethereum) authentication challenge.
///
/// The SDK signs the login challenge with the same primitive it uses for
/// transaction digests — EIP-191 `personal_sign`. Without a check on what is
/// being signed, a malicious or intercepted `/random` response can return a
/// transaction digest as the "challenge" and harvest a signature valid for
/// that transaction, while the user believes they are logging in.
///
/// Parsing the challenge and refusing anything that is not a well-formed,
/// current, human-readable sign-in message closes that path: a 32-byte digest
/// is not a SIWE message and never parses as one.
class SiweChallenge {
  final String domain;
  final String address;
  final String? uri;
  final int? chainId;
  final String nonce;
  final DateTime? issuedAt;
  final DateTime? expirationTime;
  final String raw;

  const SiweChallenge({
    required this.domain,
    required this.address,
    required this.nonce,
    required this.raw,
    this.uri,
    this.chainId,
    this.issuedAt,
    this.expirationTime,
  });

  static final RegExp _headerLine =
      RegExp(r'^(\S+) wants you to sign in with your Ethereum account:$');

  static final RegExp _bareHex = RegExp(r'^(?:0x)?[0-9a-fA-F]+$');

  /// Parse [message] as a SIWE challenge, or throw [ChallengeRejected].
  static SiweChallenge parse(String message) {
    final trimmed = message.trim();

    if (trimmed.isEmpty) {
      throw const ChallengeRejected('challenge was empty');
    }

    // The decisive check. A transaction digest, a struct hash, or any opaque
    // byte string arrives as hex; none of them is a sign-in message.
    if (_bareHex.hasMatch(trimmed)) {
      throw ChallengeRejected(
        'challenge was bare hex (${trimmed.length} chars), not a sign-in '
        'message — refusing to sign an opaque payload',
      );
    }

    final lines = trimmed.split(RegExp(r'\r?\n'));
    final header = _headerLine.firstMatch(lines.first.trim());
    if (header == null) {
      throw const ChallengeRejected(
        'challenge is not an EIP-4361 sign-in message (missing header line)',
      );
    }

    if (lines.length < 2) {
      throw const ChallengeRejected('challenge has no address line');
    }
    final address = lines[1].trim();
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) {
      throw ChallengeRejected('challenge address line is malformed: $address');
    }

    String? field(String name) {
      final prefix = '$name:';
      for (final line in lines) {
        final t = line.trim();
        if (t.startsWith(prefix)) return t.substring(prefix.length).trim();
      }
      return null;
    }

    final nonce = field('Nonce');
    if (nonce == null || nonce.isEmpty) {
      throw const ChallengeRejected('challenge carries no nonce');
    }

    DateTime? parseTime(String name) {
      final v = field(name);
      if (v == null || v.isEmpty) return null;
      return DateTime.tryParse(v)?.toUtc();
    }

    final chainIdRaw = field('Chain ID');

    return SiweChallenge(
      domain: header.group(1)!,
      address: address,
      uri: field('URI'),
      chainId: chainIdRaw == null ? null : int.tryParse(chainIdRaw),
      nonce: nonce,
      issuedAt: parseTime('Issued At'),
      expirationTime: parseTime('Expiration Time'),
      raw: message,
    );
  }

  /// Parse and validate a challenge before signing it.
  ///
  /// [expectedAddress] must be the wallet the SDK is authenticating as.
  /// [expectedChainId] is checked when supplied.
  ///
  /// [expectedDomain] is **opt-in**. Domain binding is the property that stops
  /// a challenge minted for one origin being replayed at another, so enforcing
  /// it is the stronger posture — but it is off by default because a
  /// deployment whose SIWE domain differs from the host the SDK calls would
  /// fail every login on contact. Set it once you have confirmed the two match
  /// in every environment you target.
  static SiweChallenge validate(
    String message, {
    required String expectedAddress,
    int? expectedChainId,
    String? expectedDomain,
    Duration clockSkew = const Duration(minutes: 5),
    DateTime? now,
  }) {
    final challenge = parse(message);
    final at = (now ?? DateTime.now()).toUtc();

    if (challenge.address.toLowerCase() != expectedAddress.toLowerCase()) {
      throw ChallengeRejected(
        'challenge is addressed to ${challenge.address}, not $expectedAddress',
      );
    }

    if (expectedChainId != null &&
        challenge.chainId != null &&
        challenge.chainId != expectedChainId) {
      throw ChallengeRejected(
        'challenge is bound to chain ${challenge.chainId}, '
        'but this client is configured for chain $expectedChainId',
      );
    }

    if (expectedDomain != null && challenge.domain != expectedDomain) {
      throw ChallengeRejected(
        'challenge domain ${challenge.domain} does not match the expected '
        'domain $expectedDomain',
      );
    }

    final expiry = challenge.expirationTime;
    if (expiry != null && at.isAfter(expiry.add(clockSkew))) {
      throw ChallengeRejected('challenge expired at $expiry');
    }

    final issued = challenge.issuedAt;
    if (issued != null && issued.subtract(clockSkew).isAfter(at)) {
      throw ChallengeRejected('challenge is issued in the future ($issued)');
    }

    return challenge;
  }
}
