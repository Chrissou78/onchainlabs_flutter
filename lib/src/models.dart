class PolygonWallet {
  final String address;
  final String privateKeyHex;
  final String mnemonic;

  const PolygonWallet({
    required this.address,
    required this.privateKeyHex,
    required this.mnemonic,
  });

  @override
  String toString() =>
      'PolygonWallet(address: $address, privateKeyHex: $privateKeyHex, mnemonic: $mnemonic)';
}
