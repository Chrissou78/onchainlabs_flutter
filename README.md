# onchainlabs_flutter

Polygon EVM wallet helper for Flutter mobile apps.

Goal: give you a simple way to:

- create a Polygon-compatible wallet (address + private key + mnemonic)
- sign a backend challenge
- register the wallet with `https://ga-api.onchainlabs.ch`
- store the mnemonic locally on the device
- mint tokens
- Get token balance

> Security note  
> Do not use this as your only security layer for large amounts of funds.  
> Always audit code, review storage, and consider hardware wallets for serious use.


## What it does

- Generates a BIP39 mnemonic (12 words by default).
- Derives a private key with BIP32 path `m/44'/60'/0'/0/0`.
- Builds an EVM address using `web3dart`.
- Calls `POST https://ga-api.onchainlabs.ch/random` with `{ address }`.
- Signs the returned `signMessage` with the wallet (personal sign).
- Calls `POST https://ga-api.onchainlabs.ch/register` with `{ message, signature }`.
- Stores securely the mnemonic string under the key `wlltMnic`.

The wallet is a normal Ethereum wallet, so the address type works on Polygon.

---

## Install

In your app `pubspec.yaml`:

```yaml
dependencies:
  Onchainlabs_flutter: ^2.0.1

Code Examples : 

### 1. Generate a wallet (create + register + store mnemonic)

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

Future<void> createWalletExample() async {
  final api = OnchainLabsApi();
  final manager = await PolygonWalletManager.create(api);

  final wallet = await manager.createWallet();

  print('Address: ${wallet.address}');
  print('Private key (hex): 0x${wallet.privateKeyHex}');
  print('Mnemonic: ${wallet.mnemonic}');
}

### 2. Authenticate a wallet (sign random message and send to backend)

You can authenticate either:

- the current in-memory wallet, or  
- the wallet restored from secure storage.

#### 2.1 Auth the current wallet

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

Future<void> authCurrentWalletExample(PolygonWallet wallet) async {
  final api = OnchainLabsApi();
  final manager = await PolygonWalletManager.create(api);

  final backendAddress = await manager.authenticateWallet(wallet);

  print('Backend authenticated address: $backendAddress');
}

#### 2.2 Auth the stored wallet (from secure storage)

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

Future<void> authStoredWalletExample() async {
  final api = OnchainLabsApi();
  final manager = await PolygonWalletManager.create(api);

  final backendAddress = await manager.authenticateStoredWallet();

  print('Backend authenticated stored wallet: $backendAddress');
}

### 3. Restore a wallet from a mnemonic phrase

Use this when the user already has a recovery phrase and you want to:

- rebuild the wallet (address + private key)  
- register it with the backend  
- store the mnemonic in secure storage  

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

Future<void> restoreWalletFromMnemonicExample() async {
  final api = OnchainLabsApi();
  final manager = await PolygonWalletManager.create(api);

  const userMnemonic =
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12';

  final wallet = await manager.restoreWallet(userMnemonic);

  print('Restored wallet address: ${wallet.address}');
  print('Restored private key (hex): 0x${wallet.privateKeyHex}');
}

### 4. Restore a wallet from a private key

Use this if the user owns a **raw EVM private key** (64-hex string) and needs to:

- rebuild the wallet  
- authenticate it with your backend  
- store it securely  

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

Future<void> restoreWalletFromPrivateKeyExample() async {
  final api = OnchainLabsApi();
  final manager = await PolygonWalletManager.create(api);

  const userPrivateKey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  final wallet = await manager.restoreWalletFromPrivateKey(userPrivateKey);

  print('Restored wallet address: ${wallet.address}');
}











### 5. Mint tokens and ask token balance using an API public Key

import 'package:onchainlabs_flutter/simple_onchain_api.dart';

/// Set your public key (user input in secured storage in production)
const publicKey =
    'suQxa7jxvgfQmrKQYhCT6TZxYxbmNUHrG82VPEdYy01eZ1wsQwWjUZJPSZyyapQJ';

final api = SimpleOnchainApi(publicKey: publicKey);

### 5.1 Convert Human amount (base units 6 decimals)
String toBaseUnits(String human, {int decimals = 6}) {
  if (!human.contains('.')) {
    return human + '0'.padRight(decimals, '0');
  }
  final parts = human.split('.');
  final whole = parts[0];
  var frac = parts[1];
  if (frac.length > decimals) {
    throw Exception('Too many decimals');
  }
  frac = frac.padRight(decimals, '0');
  return whole + frac;
}

### 5.2 Mint Tokens Full API mode
Future<void> mintExample(PolygonWallet wallet) async {
  final api = SimpleOnchainApi(publicKey: publicKey);

  final amount = toBaseUnits("1000"); // → "1000000000"

  final res = await api.mint(
    address: wallet.address,
    amount: amount,
    waitForTx: true,
  );

  print('Mint result: $res');
}

### 5.3 Get Token Balance
Future<void> balanceExample(PolygonWallet wallet) async {
  final api = SimpleOnchainApi(publicKey: publicKey);

  final res = await api.balanceOf(wallet.address);

  print('Balance: $res');
}
