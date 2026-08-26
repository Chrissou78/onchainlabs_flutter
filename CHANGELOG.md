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
