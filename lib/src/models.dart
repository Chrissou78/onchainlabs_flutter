class PolygonWallet {
  final String address;
  final String privateKeyHex;
  final String mnemonic;

  const PolygonWallet({
    required this.address,
    required this.privateKeyHex,
    required this.mnemonic,
  });

  /// Address only. The private key and mnemonic are deliberately excluded so
  /// that interpolating a wallet — into a log line, an exception message, a
  /// crash-reporter breadcrumb — cannot leak key material. Read the fields
  /// directly if you genuinely need them.
  @override
  String toString() => 'PolygonWallet(address: $address)';
}
