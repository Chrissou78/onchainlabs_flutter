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
  Onchainlabs_flutter: ^3.2.0

Code Examples : 

### 1. Generate a wallet (create + register + store mnemonic)

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';
import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:bip32_plus/bip32_plus.dart' as bip32;

Future<void> createWalletExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');

  // Generate mnemonic and derive private key
  final mnemonic = bip39.generateMnemonic();
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final child = root.derivePath("m/44'/60'/0'/0/0");
  final privateKeyBytes = child.privateKey!;

  // Get address
  final address = walletManager.executor.getAddressFromPrivateKey(privateKeyBytes);

  // Save to secure storage
  await walletManager.savePrivateKey(privateKeyBytes);
  await walletManager.saveAddress(address);

  print('Address: $address');
  print('Private key (hex): 0x${privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
  print('Mnemonic: $mnemonic');
}

### 2. Authenticate a wallet (sign random message and send to backend)

You can authenticate either:

- the current in-memory wallet, or  
- the wallet restored from secure storage.

#### 2.1 Auth the current wallet

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';
import 'dart:typed_data';

Future<void> authCurrentWalletExample(Uint8List privateKeyBytes) async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');

  const apiKey = 'your-api-key';

  final result = await walletManager.executor.registerAndWhitelist(
    privateKeyBytes,
    apiKey,
  );

  if (result.success) {
    print('Backend authenticated address: ${walletManager.executor.getAddressFromPrivateKey(privateKeyBytes)}');
  } else {
    print('Error: ${result.error}');
  }
}

#### 2.2 Auth the stored wallet (from secure storage)

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

Future<void> authStoredWalletExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();

  if (privateKeyBytes == null) {
    print('No wallet found in storage');
    return;
  }

  const apiKey = 'your-api-key';

  final result = await walletManager.executor.registerAndWhitelist(
    privateKeyBytes,
    apiKey,
  );

  if (result.success) {
    print('Backend authenticated stored wallet: ${await walletManager.getAddress()}');
  } else {
    print('Error: ${result.error}');
  }
}

### 3. Restore a wallet from a mnemonic phrase

Use this when the user already has a recovery phrase and you want to:

- rebuild the wallet (address + private key)  
- register it with the backend  
- store the mnemonic in secure storage  

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';
import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:bip32_plus/bip32_plus.dart' as bip32;

Future<void> restoreWalletFromMnemonicExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');

  const userMnemonic =
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12';

  final seed = bip39.mnemonicToSeed(userMnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final child = root.derivePath("m/44'/60'/0'/0/0");
  final privateKeyBytes = child.privateKey!;

  final address = walletManager.executor.getAddressFromPrivateKey(privateKeyBytes);

  await walletManager.savePrivateKey(privateKeyBytes);
  await walletManager.saveAddress(address);

  print('Restored wallet address: $address');
  print('Restored private key (hex): 0x${privateKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
}

### 4. Restore a wallet from a private key

Use this if the user owns a **raw EVM private key** (64-hex string) and needs to:

- rebuild the wallet  
- authenticate it with your backend  
- store it securely  

import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';
import 'package:hex/hex.dart';
import 'dart:typed_data';

Future<void> restoreWalletFromPrivateKeyExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');

  const userPrivateKey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  final privateKeyBytes = Uint8List.fromList(HEX.decode(userPrivateKey));
  final address = walletManager.executor.getAddressFromPrivateKey(privateKeyBytes);

  await walletManager.savePrivateKey(privateKeyBytes);
  await walletManager.saveAddress(address);

  print('Restored wallet address: $address');
}

### 5. Mint tokens and ask token balance using an API public Key

import 'package:onchainlabs_flutter/simple_onchain_api.dart';

/// Set your public key (store securely in production)
const publicKey = 'your-public-api-key';

final api = SimpleOnchainApi(publicKey: publicKey);

### 5.1 Convert Human amount (base units 6 decimals)
String toBaseUnits(String human, {int decimals = 6}) {
  if (!human.contains('.')) {
    return human + '0' * decimals;
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
Future<void> mintExample(String walletAddress) async {
  final api = SimpleOnchainApi(publicKey: publicKey);

  final amount = toBaseUnits("1000"); // → "1000000000"

  final res = await api.mint(
    address: walletAddress,
    amount: amount,
    waitForTx: true,
  );

  print('Mint result: $res');
}

### 5.3 Get Token Balance
Method A - Simple API (recommended for most cases):

Future<void> balanceExample(String walletAddress) async {
  final api = SimpleOnchainApi(publicKey: publicKey);

  final res = await api.balanceOf(walletAddress);

  print('Balance: $res');
}

Method B - Via WalletManager with signature (for authenticated requests):

CopyFuture<void> balanceExampleAuthenticated() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final address = await walletManager.getAddress();

  final balance = await walletManager.getOroCashBalanceFormatted(privateKeyBytes!, address!);

  print('Balance: $balance');
}

EIP-7702 Gasless Transactions
The SDK now supports EIP-7702 for gasless transactions. Users don't need MATIC/POL to transact.

### 6. Initialize the Wallet Manager
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

// For Polygon Amoy Testnet
final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');

// For Polygon Mainnet
final walletManager = await WalletManager.createMainnet('https://ga-api.onchainlabs.ch');

### 7. Create a Wallet with EIP-7702 Support
import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:bip32_plus/bip32_plus.dart' as bip32;

Future<void> createWalletV3Example() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');

  // Generate mnemonic and derive private key
  final mnemonic = bip39.generateMnemonic();
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final child = root.derivePath("m/44'/60'/0'/0/0");
  final privateKeyBytes = child.privateKey!;

  // Get address
  final address = walletManager.executor.getAddressFromPrivateKey(privateKeyBytes);

  // Initialize executor (caches token decimals)
  await walletManager.executor.initialize(privateKeyBytes);

  // Save to secure storage
  await walletManager.savePrivateKey(privateKeyBytes);
  await walletManager.saveAddress(address);

  print('Address: $address');
  print('Mnemonic: $mnemonic');
}

### 8. Register and Whitelist a Wallet
Future<void> registerWalletExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();

  const secretApiKey = 'your-admin-api-key';

  final result = await walletManager.executor.registerAndWhitelist(
    privateKeyBytes!,
    secretApiKey,
  );

  if (result.success) {
    print('Wallet registered and whitelisted!');
  } else {
    print('Error: ${result.error}');
  }
}

### 9. Authorize for EIP-7702 (Enable Gasless)
Future<void> authorizeWalletExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();

  final result = await walletManager.executor.authorize(
    privateKeyBytes!,
    waitForTx: true,
  );

  if (result.success) {
    print('Wallet authorized for gasless transactions!');
  }

  // Check delegation status
  final status = await walletManager.executor.getDelegationStatus(privateKeyBytes);
  print('Is delegated: ${status.isDelegated}');
}

### 10. Transfer Tokens (Gasless)
Future<void> transferExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final contractAddress = walletManager.orocashAddress!;

  // Transfer 100.5 tokens (human-readable amount)
  final result = await walletManager.executor.transferOroCashFormatted(
    privateKeyBytes!,
    contractAddress,
    '0xRecipientAddress',
    100.5,
    waitForTx: true,
  );

  if (result.success) {
    print('Transfer successful! TX: ${result.txHash}');
  } else {
    print('Transfer failed: ${result.error}');
  }
}

### 11. Buy, Sell, and Burn Tokens (Gasless)
Future<void> tokenOperationsExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final contractAddress = walletManager.orocashAddress!;
  final executor = walletManager.executor;

  // Buy tokens
  await executor.buyTokenFormatted(
    privateKeyBytes!,
    contractAddress,
    '0xRecipientAddress',
    50.0,
    waitForTx: true,
  );

  // Sell tokens
  await executor.sellTokenFormatted(
    privateKeyBytes,
    contractAddress,
    '0xRecipientAddress',
    25.0,
    waitForTx: true,
  );

  // Burn (dispose) tokens
  await executor.disposeTokenFormatted(
    privateKeyBytes,
    contractAddress,
    10.0,
    waitForTx: true,
  );
}

### 12. Approve Spender (Gasless)
Future<void> approveExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final contractAddress = walletManager.orocashAddress!;

  // Approve specific amount
  await walletManager.executor.approveFormatted(
    privateKeyBytes!,
    contractAddress,
    '0xSpenderAddress',
    1000.0,
    waitForTx: true,
  );

  // Or approve unlimited
  await walletManager.executor.approveUnlimited(
    privateKeyBytes,
    contractAddress,
    '0xSpenderAddress',
    waitForTx: true,
  );
}

### 13. Batch Transactions (Gasless)
Execute multiple operations in a single transaction:
Future<void> batchTransferExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final contractAddress = walletManager.orocashAddress!;
  final executor = walletManager.executor;

  final builder = BatchCallBuilder()
    .addTransfer(
      contractAddress: contractAddress,
      to: '0xAddress1',
      amount: executor.toRawAmount(100.0),
    )
    .addTransfer(
      contractAddress: contractAddress,
      to: '0xAddress2',
      amount: executor.toRawAmount(50.0),
    );

  final result = await executor.executeBatch(
    privateKeyBytes!,
    builder,
    waitForTx: true,
  );

  print('Batch TX: ${result.txHash}');
}

### 14. Read Token Information
Future<void> tokenInfoExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final executor = walletManager.executor;

  final name = await executor.getTokenName(privateKeyBytes!);
  final symbol = await executor.getTokenSymbol(privateKeyBytes);
  final decimals = await executor.getTokenDecimals(privateKeyBytes);
  final totalSupply = await executor.getTotalSupply(privateKeyBytes);

  print('Token: $name ($symbol)');
  print('Decimals: $decimals');
  print('Total Supply: ${executor.formatAmount(totalSupply)}');
}

### 15. Read Contract State
Future<void> contractStateExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final executor = walletManager.executor;

  final isPaused = await executor.isPaused(privateKeyBytes!);
  final hasFee = await executor.hasFee(privateKeyBytes);
  final custodyEnabled = await executor.isCustodyEnabled(privateKeyBytes);

  print('Paused: $isPaused');
  print('Has Fee: $hasFee');
  print('Custody Enabled: $custodyEnabled');
}

### 16. Read Fees (Basis Points)
Future<void> feesExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final executor = walletManager.executor;

  // Percent fee (100 bps = 1%)
  final percentFeeBps = await executor.getPercentFeeBps(privateKeyBytes!);
  final percentFeePercent = await executor.getPercentFeePercent(privateKeyBytes);

  // Fixed fee
  final fixedFee = await executor.getFixedFee(privateKeyBytes);
  final fixedFeeFormatted = await executor.getFixedFeeFormatted(privateKeyBytes);

  print('Percent Fee: $percentFeePercent%');
  print('Fixed Fee: $fixedFeeFormatted tokens');
}

### 17. Read Transaction Limits
Future<void> limitsExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final executor = walletManager.executor;
  final address = executor.getAddressFromPrivateKey(privateKeyBytes!);

  // Global limits
  final globalMin = await executor.getTxLimitGlobalMin(privateKeyBytes);
  final globalMax = await executor.getTxLimitGlobalMax(privateKeyBytes);

  // User-specific limits
  final userLimits = await executor.getUserLimit(privateKeyBytes, address);

  print('Global Limits: ${executor.formatAmount(globalMin)} - ${executor.formatAmount(globalMax)}');
  print('User Limits: ${executor.formatAmount(userLimits[0])} - ${executor.formatAmount(userLimits[1])}');
}

### 18. Check User Roles
Future<void> rolesExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final executor = walletManager.executor;
  final address = executor.getAddressFromPrivateKey(privateKeyBytes!);

  // Check specific role
  final isAdmin = await executor.hasRole(privateKeyBytes, 0, address);
  final isMinter = await executor.hasRole(privateKeyBytes, 2, address);

  print('Is Admin: $isAdmin');
  print('Is Minter: $isMinter');

  // Get all roles
  final roles = await executor.getUserRoles(privateKeyBytes, address);
  for (final entry in roles.entries) {
    final roleName = Eip7702Executor.getRoleName(entry.key);
    print('$roleName: ${entry.value}');
  }
}

// Role IDs:
// 0 = Admin
// 1 = Moderator
// 2 = Minter
// 3 = Extractor
// 4 = CFO
// 5 = Whitelist

### 19. OROCASH token = 1mg of gold
Future<void> goldPriceExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final executor = walletManager.executor;

  // Fetch gold price (cached for 5 minutes)
  final priceResult = await executor.getGoldPrice(privateKeyBytes!);

  if (priceResult.success) {
    final price = priceResult.price!;
    print('Price per mg: ${price.formattedPricePerMg}');
    print('Price per gram: ${price.formattedPricePerGram}');
    print('Price per troy oz: ${price.formattedPricePerOunce}');
  }

  // Get balance with USD value
  const publicApiKey = 'your-public-api-key';
  final address = executor.getAddressFromPrivateKey(privateKeyBytes);

  final balanceInfo = await executor.getBalanceWithUsdValue(
    privateKeyBytes,
    address,
    publicApiKey,
  );

  print('Balance: ${balanceInfo['balance']}');
  print('USD Value: ${balanceInfo['formattedUsdValue']}');
}

### 20. NFT Membership
The Orocash contract includes a soulbound NFT membership system.

Future<void> nftMembershipExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();
  final executor = walletManager.executor;

  // Check if wallet has membership
  final hasMembership = await executor.walletHasMembership(privateKeyBytes!);
  print('Has Membership: $hasMembership');

  // Get full membership info
  final membershipInfo = await executor.getWalletMembershipInfo(privateKeyBytes);

  if (membershipInfo.isMember) {
    print('Token ID: ${membershipInfo.tokenId}');
    print('Minted At: ${membershipInfo.formattedMintedAt}');
    print('Token URI: ${membershipInfo.tokenURI}');
  }

  // Get NFT collection info
  final nftName = await executor.getNftName(privateKeyBytes);
  final nftSymbol = await executor.getNftSymbol(privateKeyBytes);
  final totalMemberships = await executor.totalMemberships(privateKeyBytes);

  print('NFT: $nftName ($nftSymbol)');
  print('Total Minted: $totalMemberships');
}

### 21. Get All Contract Info
Fetch all contract information in a single call:

Future<void> allInfoExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();

  final allInfo = await walletManager.executor.getAllContractInfo(privateKeyBytes!);

  print('Token: ${allInfo['name']} (${allInfo['symbol']})');
  print('Balance: ${allInfo['balance']}');
  print('Is Paused: ${allInfo['isPaused']}');
  print('Has Fee: ${allInfo['hasFee']}');
  print('Percent Fee: ${allInfo['percentFeePercent']}%');
  print('Fixed Fee: ${allInfo['fixedFee']}');
  print('Roles: ${allInfo['roles']}');
  print('Membership: ${allInfo['membership']}');
  print('Gold Price: ${allInfo['goldPrice']}');
}

### 22. Amount Conversion Utilities
final executor = walletManager.executor;

// Human-readable to raw (with decimals)
final rawAmount = executor.toRawAmount(100.5);
print('100.5 tokens = $rawAmount raw');  // 100500000

// Raw to human-readable
final humanAmount = executor.toHumanAmount(BigInt.from(100500000));
print('100500000 raw = $humanAmount tokens');  // 100.5

// Format raw amount as string
final formatted = executor.formatAmount(BigInt.from(100500000));
print('Formatted: $formatted');  // "100.5"

### 23. Admin Operations
Future<void> adminExample() async {
  final walletManager = await WalletManager.createAmoy('https://ga-api.onchainlabs.ch');
  final privateKeyBytes = await walletManager.getPrivateKey();

  const secretApiKey = 'your-secret-api-key';

  // Mint tokens
  final mintResult = await walletManager.executor.adminMint(
    secretApiKey,
    '0xRecipientAddress',
    '1000',
  );

  // Whitelist address
  final whitelistResult = await walletManager.executor.adminWhitelist(
    privateKeyBytes!,
    secretApiKey,
    '0xWalletToWhitelist',
  );
}

