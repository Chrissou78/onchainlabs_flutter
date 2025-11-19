# onchainlabs_flutter

Polygon EVM wallet helper for Flutter mobile apps.

Goal: give you a simple way to:

- create a Polygon-compatible wallet (address + private key + mnemonic)
- sign a backend challenge
- register the wallet with `https://ga-api.onchainlabs.ch`
- store the mnemonic locally on the device

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
  Onchainlabs_flutter: ^0.0.1

Code Examples : 

### 1. Generate a wallet (create + register + store mnemonic)

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

Future<void> createWalletExample() async {
  // Use the real API
  final api = OnchainLabsApi();

  // Build manager (handles secure storage + flow)
  final manager = await PolygonWalletManager.create(api);

  // 1) Generates mnemonic
  // 2) Derives private key + address
  // 3) Calls /random + /register on backend
  // 4) Stores mnemonic in secure storage
  final wallet = await manager.createWallet();

  // Use the wallet in your app
  print('Address: ${wallet.address}');
  print('Private key (hex): 0x${wallet.privateKeyHex}');
  print('Mnemonic: ${wallet.mnemonic}');
  // these print are for testing purpose only, do not leave these for production, mnemonic and private keys must be stored in a secured location and be accessible thru an auth process in the app.
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

  // This does:
  // 1) getRandomMessage(wallet.address)
  // 2) sign the message with wallet.privateKeyHex
  // 3) call registerWallet(message, signature)
  // 4) check that backend address == wallet.address
  final backendAddress = await manager.authenticateWallet(wallet);

  print('Backend authenticated address: $backendAddress');
  // these print are for testing purpose only, do not leave these for production, mnemonic and private keys must be stored in a secured location and be accessible thru an auth process in the app.
}

#### 2.2 Auth the stored wallet (from secure storage)

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

Future<void> authStoredWalletExample() async {
  final api = OnchainLabsApi();
  final manager = await PolygonWalletManager.create(api);

  // This will:
  // 1) load mnemonic from secure storage
  // 2) derive wallet
  // 3) getRandomMessage(address)
  // 4) sign
  // 5) registerWallet
  final backendAddress = await manager.authenticateStoredWallet();

  print('Backend authenticated stored wallet: $backendAddress');
  // these print are for testing purpose only, do not leave these for production, mnemonic and private keys must be stored in a secured location and be accessible thru an auth process in the app.
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

  // The user-provided BIP39 phrase (12 or 24 words).
  // In a real app you get this from a TextField.
  const userMnemonic =
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12';

  // This will:
  // 1) validate the mnemonic
  // 2) derive private key + address
  // 3) call /random + /register with signed message
  // 4) store mnemonic in secure storage
  final wallet = await manager.restoreWallet(userMnemonic);

  print('Restored wallet address: ${wallet.address}');
  print('Restored private key (hex): 0x${wallet.privateKeyHex}');
  print('Restored mnemonic: ${wallet.mnemonic}');
  // these print are for testing purpose only, do not leave these for production, mnemonic and private keys must be stored in a secured location and be accessible thru an auth process in the app.
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

  // Private key without 0x prefix.
  // In a real app this is user input.
  const userPrivateKey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  // This will:
  // 1) rebuild EthPrivateKey
  // 2) recover the public address
  // 3) request /random
  // 4) sign the random message
  // 5) send to /register
  // 6) store private key securely inside encrypted storage
  final wallet = await manager.restoreWalletFromPrivateKey(userPrivateKey);

  print('Restored wallet address: ${wallet.address}');
  print('Restored private key (hex): 0x${wallet.privateKeyHex}');
  print('Mnemonic (if any): ${wallet.mnemonic}');
  // these print are for testing purpose only, do not leave these for production, mnemonic and private keys must be stored in a secured location and be accessible thru an auth process in the app.
}

