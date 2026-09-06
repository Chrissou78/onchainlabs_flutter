## 1.0.0

- Initial release of `onchainlabs_flutter`.
- Generate Polygon EVM wallet (address, private key, mnemonic).
- Register wallet with https://api-ga.onchainlabs.ch.
- Store mnemonic in secure storage on device.

## 2.0.1

- Add Mint function thru API
- Add Balance function thru API
- Add Test public key

## 3.1.0
- Added EIP-7702 gasless transaction support
- Added WalletManager for simplified wallet management
- Added Eip7702Executor for gasless operations
- Added batch transaction support
- Added gold price integration
- Updated fee structure to basis points (percentFeeBps, fixedFee)
- Added amount conversion utilities
- Auth headers cached for 4 hours

## 3.2.0
- Added NFT membership read functions
- Added hasMembership(), membershipOf(), getMembershipInfo()
- Added getNftName(), getNftSymbol(), totalMemberships(), getNftBaseURI()
- Updated getAllContractInfo() to include NFT membership data

## 4.0.0

### Breaking
- API hostnames migrated. Update any hardcoded `baseUrl`:
  - Production: `https://ga-api.onchainlabs.ch` → `https://api-ga.onchainlabs.ch`
  - Development: `https://dev-ga-api.onchainlabs.ch` → `https://ga-api-dev.onchainlabs.ch`
- `SimpleOnchainApi`'s default `baseUrl` changed accordingly. Callers that relied on
  the previous default will now reach a different host.

### Fixed
- `SimpleOnchainApi` defaulted to `https://dev-ga-api.onchainlabs.ch`, a host that
  resolves and serves TLS but hosts no API. Every call made without an explicit
  `baseUrl` — including `balanceOfPublic()` — failed with:
  `Exception: Request to /balance failed (status: 404, body: 404 page not found)`.
  The README examples omit `baseUrl`, so anyone following them hit this.

### Notes
- API keys are environment-specific: a development key returns
  `401 The provided API key is invalid.` against production, and vice versa. Pair each
  key with its matching host.


## 4.1.0

Security remediation from the Gens Aurea wallet integration audit (27 Aug 2026).
All changes in this release are non-breaking; no public signature changed.

### Security
- **Removed all 188 `print()` calls from the SDK** (audit L-01, L-06). The
  package no longer writes to the host application's log stream at all. Among
  the values previously printed on every run: auth signatures, server
  challenges, assembled header maps including `x-api-key`, and the admin
  `secretApiKey`. Diagnostics are now opt-in via `OnchainLabsLog.handler`,
  which redacts credentials, key material and BIP-39 phrases before emitting.
- **`PolygonWallet.toString()` no longer exposes the private key or mnemonic**
  (K-06). It returns the address only, so interpolating a wallet into a log
  line, exception message or crash-reporter breadcrumb cannot leak key
  material. Read the fields directly if you need them.
- **Contract discovery fails closed** (T-06). `WalletManager.initialize` no
  longer falls back to hard-coded delegate and token addresses when
  `/contracts` is unreachable or rejects the request; it throws
  `ContractDiscoveryException`. The delegate address determines which contract
  the wallet delegates its account to, and a network fault must not silently
  redirect that onto a different contract pair.
- **The delegation nonce no longer defaults to zero** (X-05). `authorize` and
  `executeBatchGasless` abort when the nonce cannot be established, instead of
  signing at a fixed, guessable value. "The server said 0" and "we got no
  answer" are now distinguished.
- **Addresses are validated before ABI encoding** (X-06). All six encoders,
  `_solidityPacked` and `DelegatedSigningHelper` now reject anything that is
  not exactly 20 bytes of hex. Previously `padLeft` lengthened short input but
  did not truncate long input, so an over-length address shifted every
  following 32-byte field and encoded a different call than the caller asked
  for. Note this is checked directly rather than via
  `EthereumAddress.fromHex`, whose own pattern is unanchored and whose length
  check is an `assert` — compiled out of release builds.
- **Gold prices are bounds-checked** (B-06). A quote must be finite, positive,
  inside `goldPriceMinUsdPerMg`/`goldPriceMaxUsdPerMg`, and within
  `goldPriceMaxRelativeMove` of the last validated price; otherwise the SDK
  refuses to price rather than pricing wrongly. Response parsing now accepts
  only the documented shapes, and a malformed numeric string is an error — it
  previously fell through to `?? 0.0` and was read as a valid price of zero.

### Changed
- `_parseResponse` reports `httpStatusCode` and sets `transportError: true`
  when the body was not a JSON object (D-04), so a 500 page or a captive-portal
  interception can be told apart from a genuine `{success: false}` rejection.
  Response bodies are no longer echoed into error messages.
- `DelegationStatus` gains `error` and `isKnown`. `isDelegated: false` was
  previously returned both for "not delegated" and for a failed lookup.
- Added `Eip7702Executor.checkMembership`, returning `MembershipCheck` with an
  `isKnown` flag. `hasMembership` is unchanged and still returns false on
  error; prefer `checkMembership` wherever the answer gates access.
- Added `analysis_options.yaml` with `avoid_print` as an error, so the logging
  regression cannot return silently.

### Not addressed in this release
The audit's remaining SDK findings need breaking changes and are deferred to
5.0.0: EIP-712 domain separation (X-01, X-02, X-03, X-08), removal of the admin
surface (B-04), a required `baseUrl` (T-08), build-then-sign confirmation
(X-04), `BigInt` amounts end to end (X-07), an injectable `http.Client` for
certificate pinning (T-02), and explicit secure-storage options with
user-presence binding (K-03, K-04, R-03).


## 4.2.0

No functional changes. Identical library code to 4.1.0.

This release exists to give the 4.1.0 remediation a clean, verifiable
provenance chain. The commits behind 4.1.0 were rewritten after publication,
so the commit that release was published from no longer exists and pub.dev's
link back to its source dead-ends. 4.2.0 is published from the current
history, so it can be traced back to the code it was built from.

Prefer 4.2.0 over 4.1.0. If you are on 4.1.0 the code you are running is the
same, and there is no urgency to move.

### CI
- The publish workflow now checks pub.dev before publishing and skips when the
  version is already there, so a moved or re-pushed tag no longer fails a run
  for something that is not wrong.


## 4.3.0

Continues the remediation from the Gens Aurea audit. Non-breaking: no public
signature was removed, and deprecated members still work.

### Security
- **The sign-in challenge is validated before it is signed** (X-01). The API
  now issues EIP-4361 challenges; the SDK now refuses to sign anything that is
  not a current, well-formed sign-in message addressed to this wallet on the
  configured chain. Bare hex is rejected outright, which is the decisive check:
  a transaction digest never parses as a sign-in message. Applied to both
  `/random` consumers. Rejection throws `ChallengeRejected`.
  Domain binding is available via `expectedSiweDomain` and defaults to off —
  enabling it where the challenge domain differs from the host being called
  would fail every login.
- **Auth headers no longer outlive the challenge** (partial T-04). The cache is
  bounded by the challenge's own `Expiration Time` instead of a fixed four
  hours.
- **`BatchCallBuilder.addTransfer` validates its addresses** (X-06). It had the
  same unguarded `padLeft` as the encoders fixed in 4.1.0, on a money path.
  Negative amounts are rejected.

### Added
- `Eip7702Executor.parseAmount(String)` and `parseAmountWithDecimals` — exact
  decimal parsing into base units via string arithmetic (X-07). Over-precise
  input throws rather than truncating silently.
- `WalletManager.withPrivateKey(action)` runs an operation and zeroes the key
  buffer afterwards, including on throw (R-03). `WalletManager.zeroise` is
  exposed for caller-owned buffers.
- `Eip7702Executor.requireAddressHex` is now public, for callers encoding
  their own calldata.
- `PolygonWallet` is exported. It is a required parameter of
  `SimpleOnchainApi.mint` and friends, and was previously impossible to name
  from outside the package.

### Changed
- `toRawAmount(double)` is deprecated and will be removed in 5.0.0. It no
  longer multiplies through binary floating point — it routes through the
  exact path, so the `*Formatted` write methods that call it are fixed too.
- The README has been rewritten. It previously contained a single unclosed
  code fence, so the whole document rendered as one code block, and it
  documented several methods that do not exist (`api.balanceOf`, a `mint`
  signature that was never valid, a two-argument
  `getOroCashBalanceFormatted`). It also demonstrated logging private keys and
  mnemonics — the exact pattern the audit rates Critical.

### Tests
First test coverage in the package (D-02): 28 cases across sign-in challenge
validation and amount parsing, using challenges captured verbatim from the
live API so a server-side format change fails a test rather than silently
breaking every login.


## 4.4.0

### Security
- **Contract addresses are now release constants** (T-06, and closes T-11
  permanently). `WalletManager.initialize` no longer calls `/contracts`. That
  endpoint is unauthenticated and unpinned, and its response became
  `config.delegateAddress` — the contract a wallet signs an EIP-7702
  authorisation to, the highest-consequence signature this SDK produces.
  Whoever answered the request chose it. The addresses do not change, so
  there was nothing to gain by asking.

  Pinned per chain in `kOnchainLabsContracts`, verified on-chain on
  6 September 2026 with `eth_getCode` — each address carries contract code on
  its own chain and none on the other:

  - Polygon mainnet (137): delegate `0x11a2C6C6…6BDD`, token `0x4CD6FFD0…1Fad`
  - Polygon Amoy (80002): delegate `0xAC5d44B5…b291`, token `0xcc7fA402…a8A2`

  This also removes the last route to T-11: the v3.2.0 fallback that assigned
  the gas-paying paymaster EOA to the delegate slot. A regression test asserts
  that address can never reappear in the table.

### Added
- `OnchainLabsContracts` and the `kOnchainLabsContracts` map are public, so
  integrators can read the addresses a build is pinned to.
- `initialize`, `create`, `createAmoy` and `createMainnet` accept optional
  `delegateAddress` and `tokenAddress` overrides for a private deployment or a
  chain this release does not know about. Supplying one requires the other.
  A chain with neither constants nor overrides throws
  `ContractDiscoveryException` rather than guessing.
- Both addresses are validated as 20-byte hex at initialisation, so a
  malformed one fails immediately instead of deep inside signing.

### Tests
Seven vectors pinning the address table, including that the two chains never
share an address and that the T-11 paymaster EOA is absent.


## 4.5.0

### Deprecated
- **The gold-price surface** — `getGoldPrice`, `getBalanceWithUsdValue`, and
  by extension `GoldPrice`, `GoldPriceResult` and the `goldPrice*` tuning
  fields. Removal in 5.0.0.

  It has no known consumer. The Gens Aurea application takes a EUR-per-gram
  price from its own backend and never calls this path, and a USD-per-milligram
  figure is not directly usable by a product priced in euros without an FX rate
  the SDK does not supply.

  This also settles audit finding B-06 by removing the thing rather than
  hardening it further. The bounds and drift check added in 4.1.0 remain in
  place until the surface goes, so nothing regresses in the meantime — but they
  were never protecting the price customers actually see, which comes from a
  different backend with no validation of its own.

  If you price a value-bearing action, the right shape is a server-issued quote
  carrying a signature the client verifies, with a short expiry. A client
  reading a bare number off an endpoint cannot tell a real price from one an
  interception chose.

Nothing was removed. Deprecated members still work, and internal callers were
routed off them so the deprecation produces no warnings inside the package.

### Changed — R-03, partial
- `savePrivateKey` and `getPrivateKey` no longer scatter key material across
  immutable strings. Saving allocated one two-character string per byte plus
  the joined result — 33 copies for a 32-byte key, none of which can be
  overwritten. Reading called `substring` per byte, leaving 32 more, and built
  a growable list that reallocated before being copied again. Both now work
  through a pre-sized byte buffer that is zeroed afterwards.

  The encoding is byte-identical to the previous implementation, verified
  across all 256 byte values, so keys already in storage decode unchanged.
  Malformed stored hex now raises `FormatException` instead of failing
  obscurely mid-parse.

  One string still reaches the platform, because `flutter_secure_storage`
  takes a string and Dart cannot zero one. R-03 therefore remains partially
  remediated: `withPrivateKey` bounds the buffer's lifetime, this bounds the
  number of unclearable copies, and the structural remedy is still a
  hardware-backed key where the raw bytes never enter the process — 5.0.0,
  with K-03 and K-04.

## 4.6.0

### Security
- **iOS Keychain accessibility is no longer the plugin default** (K-03, iOS
  half). The SDK's own storage now uses
  `KeychainAccessibility.first_unlock_this_device` instead of `unlocked`, so
  key material is no longer eligible for encrypted iTunes and iCloud backups
  and does not migrate to a restored device.

  Safe on upgrade: the iOS plugin's `read` does not filter on this attribute,
  so keys already stored stay readable. It applies to writes, and iOS does not
  allow changing it via update — an existing key keeps the weaker attribute
  until it is written again.

### Added
- `create`, `createAmoy` and `createMainnet` accept `iosOptions` and
  `androidOptions`, exposed as `WalletManager.defaultIosOptions` and
  `defaultAndroidOptions`.

### Deliberately not changed
- **Android still uses the plugin default**, not
  `encryptedSharedPreferences: true`. The Android half of K-03 asks for it,
  but that selects a different backing store and the plugin requires the same
  setting on *every* `FlutterSecureStorage` in the process. A library that
  flipped it unilaterally would risk mixed-usage errors and unreadable data in
  the host application, which keeps its own instances.

  Enable it from the app, passing the same options to `WalletManager` and to
  every instance you construct yourself, and plan a migration for data already
  written. K-03 is marked `OWNER Both` in the audit for exactly this reason:
  the SDK supplies the knob, the application decides when to turn it.
