# onchainlabs_flutter

Polygon EVM wallet helper for Flutter mobile apps.

Goal: give you a simple way to:

- create a Polygon-compatible wallet (address + private key + mnemonic)
- sign a backend challenge
- register the wallet with `https://ga-api.onchainlabs.ch`
- store the mnemonic locally on the device

This package is a Dart / Flutter port of a TypeScript flow based on `ethers.Wallet`.

> Security note  
> Do not use this as your only security layer for large amounts of funds.  
> Always audit code, review storage, and consider hardware wallets for serious use.

---

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
