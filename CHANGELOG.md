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
