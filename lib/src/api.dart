abstract class PolygonWalletApi {
  Future<String> getRandomMessage(String address);
  Future<String> registerWallet(String message, String signature);
}

