// lib/src/logging.dart

/// Signature for a host-supplied log sink.
typedef OnchainLabsLogHandler = void Function(String message);

/// Diagnostic logging for the OnchainLabs SDK.
///
/// The SDK writes nothing to the host application's log stream by default.
/// A host that wants diagnostics installs a handler explicitly:
///
/// ```dart
/// OnchainLabsLog.handler = (m) => debugPrint('[onchainlabs] $m');
/// ```
///
/// Messages are passed through [redact] before they reach the handler, so a
/// key, signature or credential that reaches a log call by accident is masked
/// rather than emitted. Redaction is a backstop, not a licence: secret material
/// should never be passed to [log] in the first place.
class OnchainLabsLog {
  OnchainLabsLog._();

  /// The active log sink, or null (the default) to discard all messages.
  static OnchainLabsLogHandler? handler;

  /// Whether a handler is installed. Guard expensive message construction:
  /// `if (OnchainLabsLog.isEnabled) OnchainLabsLog.log(expensive());`
  static bool get isEnabled => handler != null;

  /// Emit [message] to the installed handler, after redaction. No-op when no
  /// handler is installed.
  static void log(String message) {
    final h = handler;
    if (h == null) return;
    h(redact(message));
  }

  // Header and field names whose values must never be emitted. Matches
  // `name: value`, `name=value` and `"name": "value"` shapes.
  static final RegExp _sensitiveField = RegExp(
    r'''(?<name>authorization|x-api-key|x-signature|x-message|secretApiKey|apiKey|privateKey|privateKeyHex|mnemonic|seed|seedPhrase|password)'''
    // The value is one whitespace-free token, optionally preceded by an auth
    // scheme. Without the scheme alternative, `authorization: Bearer <jwt>`
    // masks the word "Bearer" and leaves the token itself in the message.
    r'''(?<sep>"?\s*[:=]\s*"?)(?<value>(?:(?:Bearer|Basic|Token|Digest)\s+)?[^,}\s"]+)''',
    caseSensitive: false,
  );

  // Bare hex blobs long enough to be a private key (32 bytes) or an ECDSA
  // signature (65 bytes). Digests are the same width as keys, so this masks
  // some non-secret values too — that trade is deliberate.
  static final RegExp _hexBlob = RegExp(r'\b(?:0x)?[0-9a-fA-F]{64,}\b');

  // BIP-39 phrases: 12 words, then any number of further groups of three,
  // which covers the valid 12/15/18/21/24 lengths. Deliberately narrower than
  // "any 12-to-24 short words" so ordinary prose is less likely to trip it.
  //
  // This over-redacts by design: an English sentence of twelve short
  // lowercase words will be masked. Losing a log line is the right side of
  // this trade against emitting a seed phrase.
  static final RegExp _mnemonicPhrase = RegExp(
    r'\b(?:[a-z]{3,8}\s+){11}(?:(?:[a-z]{3,8}\s+){3})*[a-z]{3,8}\b',
  );

  /// Mask credentials and key material in [message].
  ///
  /// Order is load-bearing. The phrase and hex patterns run *before* the
  /// field pattern: `_sensitiveField` stops its value at the first space, so
  /// on `mnemonic: word1 word2 ... word12` it would mask only `word1` and
  /// leave the remaining eleven words in the message — and by then too few
  /// would remain for the phrase pattern to recognise what it was.
  static String redact(String message) {
    var out = message.replaceAll(_mnemonicPhrase, '<redacted:phrase>');
    out = out.replaceAll(_hexBlob, '<redacted:hex>');
    out = out.replaceAllMapped(_sensitiveField, (m) {
      // replaceAllMapped is typed to Match, but a RegExp always yields a
      // RegExpMatch — which is where namedGroup lives.
      final match = m as RegExpMatch;
      return '${match.namedGroup('name')}${match.namedGroup('sep')}<redacted>';
    });
    return out;
  }
}
