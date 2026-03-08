# 🪙 Presale

![Base](https://img.shields.io/badge/Base-Blockchain-0052FF?logo=coinbase&logoColor=white)
![Solidity](https://img.shields.io/badge/Solidity-0.8.30-363636?logo=solidity)
![Chainlink](https://img.shields.io/badge/Oracle-Chainlink-375BD2?logo=chainlink&logoColor=white)
![Foundry](https://img.shields.io/badge/Framework-Foundry-red)
![License](https://img.shields.io/badge/License-MIT-green)

**Presale** is a **DeFi-focused Solidity project** built on **Base**, designed to manage a token presale with multi-token payment support and on-chain price validation via **Chainlink oracles**.

This project showcases production-style smart contract development, including oracle integration, ERC20 payment flows, and owner-controlled emergency mechanisms.

---

## 🚀 Why This Project Matters

This repository demonstrates:

- ✅ Multi-token presale architecture with **whitelisted ERC20 payments**
- ✅ Direct **Chainlink Price Feed** integration with per-token staleness protection
- ✅ Support for **USDC, USDbC and cbBTC** on Base mainnet
- ✅ Owner-controlled token whitelist management
- ✅ Emergency ERC20 withdrawal mechanism
- ✅ Clean oracle abstraction via `SecureChainlinkOracle`
- ✅ Fully tested with **Foundry** against a Base mainnet fork

It reflects practical knowledge of how token sales interact with real DeFi infrastructure on-chain.

---

## 🧠 What The Protocol Does

### 🛒 Token Presale

Users can purchase presale tokens by paying with any whitelisted ERC20 token.

Key points:

- Configurable list of accepted payment tokens
- Each payment token is paired with a Chainlink price feed
- Prices are validated on-chain to ensure fair token allocation
- Oracle staleness thresholds are enforced per token to prevent stale price usage

---

## 🏗️ Technical Highlights

- Solidity 0.8.30 with strict safety checks
- Chainlink oracle integration with per-feed staleness enforcement
- Multi-token ERC20 payment support
- Ownable access control pattern
- Modular oracle abstraction layer
- Fork-based integration tests using Foundry

> Note: Slippage and price impact protection is handled at the oracle level through staleness thresholds, not enforced as a slippage percentage within the purchase logic.

---

## 📦 Project Structure

```text
.
├── src/        → Core presale, token, and oracle contracts
├── test/       → Integration tests (fork-based against Base mainnet)
├── script/     → Deployment scripts
└── lib/        → Dependencies (OpenZeppelin, Chainlink, etc.)
```

---

## 🌐 Whitelisted Tokens on Base

| Token  | Address | Price Feed | Staleness Threshold |
|--------|---------|------------|-------------------|
| cbBTC  | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | `0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F` | 1 hour |
| USDC   | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` | 3 days |
| USDbC  | `0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA` | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` | 3 days |

---

## 🛠 Tech Stack

- Solidity 0.8.30
- Chainlink Data Feeds
- OpenZeppelin ERC20
- Foundry (Forge + Cast + Anvil)
- Base (L2 — OP Stack)

---

## 🔍 Example Interaction Flow

### Buy Presale Tokens

1. Approve a whitelisted token (e.g. USDC) to the Presale contract.
2. Call the purchase function with the desired amount.
3. Contract validates the Chainlink price and staleness.
4. Presale tokens are allocated to the buyer.

### Owner: Add a Payment Token

1. Call `addWhitelistedToken(tokenAddress, priceFeed, stalenessThreshold)`.
2. Token is registered with its oracle and threshold.
3. Users can now pay with that token.

### Owner: Emergency Withdrawal

1. Call `emergencyERC20Withdraw(tokenAddress)`.
2. Full balance of that token is transferred to the owner.

---

## 🧪 Running Tests

Tests run against a **Base mainnet fork** to interact with real deployed contracts (Chainlink feeds, USDC, etc.):

```bash
# Run all tests
forge test --fork-url https://mainnet.base.org

# Run a specific test with full trace
forge test -vvvv --fork-url https://mainnet.base.org --match-test <testName>
```

---

## 🧠 What This Demonstrates (For Recruiters)

This project proves:

- Understanding of **oracle security** and staleness attack vectors
- **Multi-token payment** architecture in presale contracts
- ERC20 approval and token flow handling in Solidity
- Integration of **real mainnet infrastructure** (Chainlink, USDC on Base)
- Fork-based testing with Foundry for production-like coverage
- Clean contract separation of concerns (sale logic vs oracle logic)

---

## 👤 Author

Developed by **Javier Herrador**  
Blockchain & Solidity Developer focused on DeFi infrastructure and protocol mechanics.