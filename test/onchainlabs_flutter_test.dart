import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

class _Api implements PolygonWalletApi {
  @override
  Future<String> getRandomMessage(String address) async {
    // Include address in the message so we can extract it.
    return 'Sign this: $address';
  }

  @override
  Future<String> registerWallet(String message, String signature) async {
    const prefix = 'Sign this: ';
    if (!message.startsWith(prefix)) {
      throw Exception('Unexpected message format: $message');
    }
    final addr = message.substring(prefix.length).trim();
    return addr;
  }
}

void main() {
  // 1) Initialize Flutter test binding
  TestWidgetsFlutterBinding.ensureInitialized();

  // 2) Mock flutter_secure_storage method channel
  const MethodChannel channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      // minimal in-memory fake
      switch (call.method) {
        case 'write':
          return null;
        case 'read':
          return null; // always "no value"
        case 'delete':
          return null;
        case 'readAll':
          return <String, String>{};
        case 'containsKey':
          return false;
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('createWallet returns a wallet with mnemonic and private key', () async {
    final api = _Api();
    final manager = await PolygonWalletManager.create(api);

    final wallet = await manager.createWallet();

    print('mnemonic=${wallet.mnemonic}');
    print('privateKey=${wallet.privateKeyHex}');
    print('address=${wallet.address}');

    // address: just check non-empty
    expect(wallet.address.isNotEmpty, true);

    // private key must be 64 hex chars
    expect(wallet.privateKeyHex.length, 64);

    // mnemonic must have at least 12 words
    final words = wallet.mnemonic.trim().split(RegExp(r'\s+'));
    expect(words.length >= 12, true);
  });
}
