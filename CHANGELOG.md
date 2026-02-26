## 1.0.0

- Initial release of `onchainlabs_flutter`.
- Generate Polygon EVM wallet (address, private key, mnemonic).
- Register wallet with https://ga-api.onchainlabs.ch.
- Store mnemonic in secure storage on device.

## 2.0.1

- Add Mint function thru API
- Add Balance function thru API
- Add Test public key

## 3.2.0
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