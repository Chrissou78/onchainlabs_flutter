# onchainlabs_flutter

Polygon EVM wallet helper for Flutter mobile apps.

- create a Polygon-compatible wallet (address + private key + mnemonic)
- authenticate against the OnchainLabs API with a signed sign-in challenge
- read and move OROCASH tokens, including gasless transfers via EIP-7702
- read gold prices, contract state, fees, limits, roles and NFT membership

The wallet is an ordinary Ethereum wallet, so the address works on Polygon.

---

## Security posture

Read this before shipping. It is short and it matters.

**Key material lives on the device.** The private key is held in
`FlutterSecureStorage` with platform defaults. It is not hardware-backed, not
bound to user presence, and not excluded from OS backups. If you are holding
value on it, add those controls at the app level.

**Never log key material.** The SDK writes nothing to your log stream by
default — see [Diagnostics](#diagnostics). Do not undo that by printing wallets,
mnemonics or private keys yourself. A recovery phrase cannot be rotated.

**Transaction signing has known limitations in 4.x.** The signed payload does
not carry a chain ID or verifying contract, and the batch encoding is not
injective. If you operate on more than one chain, or rely on the SDK's batch
path for high-value transfers, understand those limits first. See
[Known limitations](#known-limitations).

**Use certificate pinning.** The SDK has none. Prefer OS-level pinning
(`NSPinnedDomains` on iOS, `network_security_config.xml` on Android) so it
covers every client in your app.

---

## Install

```yaml
dependencies:
  onchainlabs_flutter: ^4.3.0
```

```dart
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';
```

Requires Dart `>=3.6.0 <4.0.0` and Flutter `>=3.10.0`.

---

## Environments

| Environment | Base URL |
|---|---|
| Production | `https://api-ga.onchainlabs.ch` |
| Development | `https://ga-api-dev.onchainlabs.ch` |

**API keys are environment-specific.** A development key returns
`401 The provided API key is invalid.` against production, and the reverse.
Pair each key with its matching host.

`SimpleOnchainApi` defaults to the **development** host. Pass `baseUrl`
explicitly in production rather than relying on the default:

```dart
final api = SimpleOnchainApi(
  publicKey: publicKey,
  baseUrl: 'https://api-ga.onchainlabs.ch',
);
```

`WalletManager` has no default — the base URL is a required argument.

---

## Quick start

```dart
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

final walletManager = await WalletManager.createAmoy(
  'https://ga-api-dev.onchainlabs.ch',
);

// Runs the operation with the key, then zeroes the buffer.
final balance = await walletManager.withPrivateKey(
  (key) => walletManager.executor.getOroCashBalanceFromWallet(key),
);

print('Balance: ${walletManager.executor.formatAmount(balance)}');
```

---

## Wallets

### 1. Create a wallet

```dart
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';
import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:bip32_plus/bip32_plus.dart' as bip32;

Future<String> createWallet(WalletManager walletManager) async {
  final mnemonic = bip39.generateMnemonic();
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final child = root.derivePath("m/44'/60'/0'/0/0");
  final privateKeyBytes = child.privateKey!;

  final address = walletManager.executor.getAddressFromPrivateKey(privateKeyBytes);

  await walletManager.savePrivateKey(privateKeyBytes);
  await walletManager.saveAddress(address);

  // Show the mnemonic to the user once, require confirmation, then discard it.
  // Do NOT log it and do NOT persist it alongside the key.
  return mnemonic;
}
```

The mnemonic is returned to you and **not persisted by the library**. Storing
it is your decision; if you do, put it behind the same protection as the key.

### 2. Restore from a mnemonic

```dart
Future<void> restoreFromMnemonic(
  WalletManager walletManager,
  String userMnemonic,
) async {
  final seed = bip39.mnemonicToSeed(userMnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final child = root.derivePath("m/44'/60'/0'/0/0");
  final privateKeyBytes = child.privateKey!;

  final address = walletManager.executor.getAddressFromPrivateKey(privateKeyBytes);

  await walletManager.savePrivateKey(privateKeyBytes);
  await walletManager.saveAddress(address);
}
```

### 3. Restore from a private key

```dart
import 'dart:typed_data';
import 'package:hex/hex.dart';

Future<void> restoreFromPrivateKey(
  WalletManager walletManager,
  String userPrivateKeyHex, // 64 hex chars, no 0x
) async {
  final privateKeyBytes = Uint8List.fromList(HEX.decode(userPrivateKeyHex));
  final address = walletManager.executor.getAddressFromPrivateKey(privateKeyBytes);

  await walletManager.savePrivateKey(privateKeyBytes);
  await walletManager.saveAddress(address);
}
```

### 4. Register and whitelist

```dart
Future<void> register(WalletManager walletManager, String apiKey) async {
  final result = await walletManager.withPrivateKey(
    (key) => walletManager.executor.registerAndWhitelist(key, apiKey),
  );

  if (!result.success) {
    print('Registration failed: ${result.error}');
  }
}
```

> `registerAndWhitelist` takes a privileged API key. See
> [Admin operations](#admin-operations) before shipping it in an app.

---

## Key handling

`withPrivateKey` reads the key, runs your operation, and zeroes the buffer
afterwards — including if the operation throws. Prefer it over `getPrivateKey`
for one-off work.

```dart
final status = await walletManager.withPrivateKey(
  (key) => walletManager.executor.getDelegationStatus(key),
);
```

Do not retain the buffer past the callback: it will be zeros. If you hold your
own copy, clear it yourself:

```dart
WalletManager.zeroise(myKeyBuffer);
```

This narrows exposure rather than eliminating it. Anything the key is passed to
may copy it, and Dart strings cannot be zeroed at all.

Clear everything on logout:

```dart
await walletManager.deleteWallet(); // deletes the key and clears the auth cache
```

---

## Amounts

Token amounts are integers in base units. **Parse decimal input as a string**,
never through a `double`:

```dart
final executor = walletManager.executor;

final raw = executor.parseAmount('100.5');       // exact
final text = executor.formatAmount(raw);         // "100.5"
```

`parseAmount` throws `FormatException` on malformed input, or on more decimal
places than the token has, rather than silently truncating the user's amount.

If you know the precision without an initialised executor:

```dart
final raw = Eip7702Executor.parseAmountWithDecimals('100.5', 6);
```

> **Deprecated:** `toRawAmount(double)` is deprecated and will be removed in
> 5.0.0. Binary floating point cannot represent most decimal fractions exactly,
> and above roughly 9×10¹⁵ base units it cannot represent the value at all.
> `toHumanAmount` returns a `double` and is for display only — never feed its
> result back into a transaction.

---

## API access without a wallet

`SimpleOnchainApi` covers the endpoints that need only a public API key.

```dart
final api = SimpleOnchainApi(
  publicKey: publicKey,
  baseUrl: 'https://api-ga.onchainlabs.ch',
);

final res = await api.balanceOfPublic(walletAddress);
// {address: 0x..., balance: "1000000", success: true}
```

Write operations need a wallet to sign with:

```dart
final wallet = PolygonWallet(
  address: address,
  privateKeyHex: privateKeyHex,
  mnemonic: mnemonic,
);

final res = await api.mint(
  signerWallet: wallet,
  contractAddress: contractAddress,
  receiver: walletAddress,
  amountHuman: '1000',   // decimal string, converted exactly
  waitForTx: true,
);
```

`transfer`, `transferFrom`, `buyToken`, `sellToken`, `approve` and
`checkAccount` follow the same shape.

---

## EIP-7702 gasless transactions

Users do not need MATIC/POL to transact.

### 5. Initialise

```dart
// Polygon Amoy testnet
final walletManager = await WalletManager.createAmoy(baseUrl);

// Polygon mainnet
final walletManager = await WalletManager.createMainnet(baseUrl);
```

Contract addresses are **compiled in**, not fetched. `/contracts` is
unauthenticated and unpinned, and its answer becomes the contract your wallet
delegates its account to — so whoever answered that request would choose it.
The addresses don't change, so there is nothing to gain by asking.

| Chain | Delegate | Token |
|---|---|---|
| Polygon mainnet (137) | `0x11a2C6C6…6BDD` | `0x4CD6FFD0…1Fad` |
| Polygon Amoy (80002) | `0xAC5d44B5…b291` | `0xcc7fA402…a8A2` |

Read what a build is pinned to via `kOnchainLabsContracts`. For a private
deployment or a chain this release doesn't know, pass both explicitly:

```dart
final walletManager = await WalletManager.create(
  baseUrl: baseUrl,
  rpcUrl: rpcUrl,
  chainId: 1337,
  delegateAddress: '0x…',
  tokenAddress: '0x…',
);
```

A chain with neither compiled-in constants nor overrides throws
`ContractDiscoveryException` rather than guessing:

```dart
try {
  final walletManager = await WalletManager.createAmoy(baseUrl);
} on ContractDiscoveryException catch (e) {
  // Unknown chain and no addresses supplied. Do not proceed.
}
```

### 6. Authorize (enable gasless)

```dart
final result = await walletManager.withPrivateKey(
  (key) => walletManager.executor.authorize(key, waitForTx: true),
);

final status = await walletManager.withPrivateKey(
  (key) => walletManager.executor.getDelegationStatus(key),
);

if (status.isKnown) {
  print('Delegated: ${status.isDelegated}');
} else {
  print('Could not determine delegation: ${status.error}');
}
```

`isDelegated == false` alone is ambiguous — it is also what a failed lookup
returns. Check `isKnown` before treating it as authoritative.

### 7. Transfer

```dart
final executor = walletManager.executor;
final contractAddress = walletManager.orocashAddress!;

final result = await walletManager.withPrivateKey(
  (key) => executor.transferOroCash(
    key,
    contractAddress,
    '0xRecipientAddress',
    executor.parseAmount('100.5'),
    waitForTx: true,
  ),
);

if (result.success) {
  print('TX: ${result.txHash}');
}
```

### 8. Buy, sell, burn

```dart
await executor.buyToken(key, contractAddress, recipient, executor.parseAmount('50'));
await executor.sellToken(key, contractAddress, recipient, executor.parseAmount('25'));
await executor.disposeToken(key, contractAddress, executor.parseAmount('10'));
```

### 9. Approve

```dart
await executor.approve(
  key,
  contractAddress,
  '0xSpenderAddress',
  executor.parseAmount('1000'),
);

await executor.approveUnlimited(key, contractAddress, '0xSpenderAddress');
```

### 10. Batch

```dart
final builder = BatchCallBuilder()
  .addTransfer(
    contractAddress: contractAddress,
    to: '0xAddress1',
    amount: executor.parseAmount('100'),
  )
  .addTransfer(
    contractAddress: contractAddress,
    to: '0xAddress2',
    amount: executor.parseAmount('50'),
  );

final result = await executor.executeBatch(key, builder, waitForTx: true);
```

> See [Known limitations](#known-limitations) on batch encoding before using
> this for high-value transfers.

---

## Reads

### 11. Token information

```dart
final name = await executor.getTokenName(key);
final symbol = await executor.getTokenSymbol(key);
final decimals = await executor.getTokenDecimals(key);
final totalSupply = await executor.getTotalSupply(key);

print('$name ($symbol), ${executor.formatAmount(totalSupply)}');
```

### 12. Contract state, fees and limits

```dart
final isPaused = await executor.isPaused(key);
final hasFee = await executor.hasFee(key);
final custodyEnabled = await executor.isCustodyEnabled(key);

// 100 bps = 1%
final percentFeeBps = await executor.getPercentFeeBps(key);
final fixedFee = await executor.getFixedFee(key);

final globalMin = await executor.getTxLimitGlobalMin(key);
final globalMax = await executor.getTxLimitGlobalMax(key);
final userLimits = await executor.getUserLimit(key, address);
```

### 13. Roles

```dart
final isAdmin = await executor.hasRole(key, 0, address);
final roles = await executor.getUserRoles(key, address);

for (final entry in roles.entries) {
  print('${Eip7702Executor.getRoleName(entry.key)}: ${entry.value}');
}
```

| ID | Role | ID | Role |
|---|---|---|---|
| 0 | Admin | 3 | Extractor |
| 1 | Moderator | 4 | CFO |
| 2 | Minter | 5 | Whitelist |

### 14. Gold price

One OROCASH represents 1mg of gold.

```dart
final priceResult = await executor.getGoldPrice(key);

if (priceResult.success) {
  final price = priceResult.price!;
  print('Per mg:   ${price.formattedPricePerMg}');
  print('Per gram: ${price.formattedPricePerGram}');
}
```

Quotes are validated before use: a price must be finite, positive, inside
`goldPriceMinUsdPerMg`/`goldPriceMaxUsdPerMg`, and within
`goldPriceMaxRelativeMove` of the last accepted price. Otherwise the SDK
refuses to price rather than pricing wrongly. Tune the bands for your own risk
appetite:

```dart
executor.goldPriceMinUsdPerMg = 0.005;
executor.goldPriceMaxUsdPerMg = 1.0;
executor.goldPriceMaxRelativeMove = 0.5; // or null to disable
```

These are a sanity check, not a market-data control. Without certificate
pinning, an interception still sets the price a user sees within those bands.

### 15. NFT membership

```dart
final check = await executor.checkMembership(key, address);

if (!check.isKnown) {
  print('Could not verify membership: ${check.error}');
} else if (check.hasMembership) {
  final info = await executor.getWalletMembershipInfo(key);
  print('Token ID: ${info.tokenId}, minted ${info.formattedMintedAt}');
}
```

Prefer `checkMembership` over `hasMembership` anywhere the answer gates
access: `hasMembership` returns `false` both for "no membership" and for
"the check failed".

### 16. Everything at once

```dart
final allInfo = await executor.getAllContractInfo(key);
```

### 17. Wallet status

```dart
final result = await executor.getWalletStatus(key);

if (result.success) {
  final data = result.data!;
  print('Whitelisted: ${data['whitelisted']}');
  print('Delegated: ${data['delegated']}');
} else if (result.error?.contains('Wallet not found') == true) {
  print('Not registered — call registerAndWhitelist first');
}
```

| Field | Type | Description |
|---|---|---|
| `whitelisted` | `bool` | Wallet has the Whitelist role and can transact |
| `delegated` | `bool` | EIP-7702 delegation is active (gasless enabled) |
| `roles` | `List` | Role IDs assigned to the wallet |

---

## Sign-in challenge validation

The SDK authenticates by signing an EIP-4361 (Sign-In with Ethereum) challenge
from `POST /random`. Because authentication and transaction signing share the
same primitive, a challenge is validated before it is signed: it must parse as
a current, well-formed sign-in message addressed to this wallet, on the
configured chain. Opaque payloads — a transaction digest, for instance — are
rejected outright.

Rejection throws `ChallengeRejected`:

```dart
try {
  final headers = await executor.createAuthHeaders(key);
} on ChallengeRejected catch (e) {
  // The server did not return a challenge we are willing to sign.
  print(e.reason);
}
```

**Domain binding is opt-in.** Setting it is the stronger posture, but it will
fail every login if the challenge's domain differs from the host you call, so
confirm they agree in each environment first:

```dart
executor.expectedSiweDomain = 'api-ga.onchainlabs.ch';
```

`SimpleOnchainApi` takes the same settings at construction:

```dart
final api = SimpleOnchainApi(
  publicKey: publicKey,
  baseUrl: 'https://api-ga.onchainlabs.ch',
  chainId: 137,
  expectedSiweDomain: 'api-ga.onchainlabs.ch',
);
```

---

## Diagnostics

The SDK writes **nothing** to your log stream unless you ask it to.

```dart
OnchainLabsLog.handler = (message) => debugPrint('[onchainlabs] $message');
```

Messages pass through a redactor that masks API keys, signatures, bearer
tokens, private keys and BIP-39 phrases. Treat that as a backstop, not a
licence: never pass secret material to a log call.

Disable again by setting `handler` to `null`.

---

## Error handling

| Type | Raised when |
|---|---|
| `ContractDiscoveryException` | Contract addresses could not be established at initialisation |
| `ChallengeRejected` | The sign-in challenge was not something the SDK will sign |
| `FormatException` | An amount was malformed or too precise for the token |
| `ArgumentError` | An address was not 20 bytes of hex |

API responses carry `httpStatusCode`, and set `transportError: true` when the
body was not a JSON object at all — a proxy error page or a captive portal,
rather than a genuine rejection by the API:

```dart
if (result['transportError'] == true) {
  // Do not treat this as an authoritative "no".
}
```

---

## Admin operations

`adminMint`, `adminWhitelist` and `registerAndWhitelist` take a privileged API
key.

> **Do not ship an admin key in a mobile app.** Anything in the binary is
> extractable, and rotating a leaked key does not help when the replacement
> ships the same way. Have your backend perform privileged operations in
> response to an authenticated user action instead.
>
> This surface is scheduled for removal in 5.0.0.

```dart
final result = await walletManager.executor.adminMint(
  secretApiKey,
  '0xRecipientAddress',
  '1000',
);
```

---

## Migrating from 3.x

| Change | Action |
|---|---|
| API hostnames changed | `ga-api` → `api-ga`, `dev-ga-api` → `ga-api-dev` |
| SDK no longer prints anything | Set `OnchainLabsLog.handler` if you relied on its output |
| `PolygonWallet.toString()` returns the address only | Read fields directly if you need them |
| Contract discovery fails closed | Handle `ContractDiscoveryException` |
| Challenges are validated | Handle `ChallengeRejected` |
| `toRawAmount(double)` deprecated | Use `parseAmount(String)` |
| Nonce fetch failures abort | Signing no longer proceeds at nonce 0 |
| Addresses are validated | Malformed addresses now throw instead of encoding wrongly |

No public signature was removed in 4.x. Deprecated members still work.

---

## Known limitations

Carried from the 2026 security review; scheduled for 5.0.0.

- **No domain separation between signing contexts.** Authentication and
  transaction signing use the same EIP-191 primitive. Challenge validation
  closes the practical path, but EIP-712 typed signing is the real fix.
- **Signed payloads omit chain ID and verifying contract.** A signature is
  valid on any chain and against any deployment of the same scheme.
- **Batch encoding is not injective.** Variable-length call data is
  concatenated without length prefixes, so distinct batches can produce the
  same digest.
- **No certificate pinning**, and no way to inject your own `http.Client`.
- **No confirmation binding.** Nothing ties what a user approves on screen to
  the bytes that get signed.
- **Secure storage uses platform defaults** — not hardware-backed, no
  user-presence requirement, not excluded from OS backups.
- **The admin surface exists on the client.** See above.

---

## License

MIT — see [LICENSE](LICENSE).
