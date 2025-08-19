# NFT Fractionalization Contract

A Clarity smart contract for **fractionalizing NFTs into tradeable fungible fractions**.  
This enables shared ownership, trading, governance, and revenue distribution for NFTs on the Stacks blockchain.

---

## 🚀 Features

- **NFT Creation**
  - Mint original NFTs with metadata (name, description, image, category, rarity, estimated value).

- **Fractionalization**
  - Lock NFTs in a vault.
  - Split ownership into fungible fraction tokens.
  - Set minimum bid per fraction and buyout threshold.

- **Marketplace**
  - List fractions for sale.
  - Buy fractions directly from listings.
  - Track trading volume and last trade price.

- **Buyouts**
  - Propose buyouts for fractionalized NFTs.
  - Voting system weighted by fractions owned.
  - Escrowed buyout funds.
  - Execute successful buyouts and distribute proceeds to fraction holders.

- **Revenue Distribution**
  - Distribute external revenue (e.g., royalties, rental income).
  - Fraction holders can claim their share.
  - Maintains revenue history and pending claims.

- **Governance**
  - On-chain proposals (e.g., metadata update, revenue distribution strategy).
  - Voting with fraction ownership weight.

- **Valuation System**
  - Tracks valuation history from trades, appraisals, and buyouts.
  - Provides price discovery for NFT fractions.

---

## 📂 Contract Structure

### Data Structures
- **`nft-metadata`** → Metadata for each original NFT.
- **`fractionalized-nfts`** → Records fractionalization details.
- **`fraction-ownership`** → Tracks fractions owned per address.
- **`fraction-listings`** → Marketplace listings for fractions.
- **`buyout-proposals`** & **`buyout-votes`** → Buyout governance system.
- **`revenue-pools`** & **`revenue-claims`** → Revenue distribution system.
- **`governance-proposals`** → Decentralized governance per NFT.
- **`valuation-history`** → Tracks NFT valuation events.

### Key Variables
- `nft-counter` → Total NFTs minted.
- `listing-counter` → Total listings created.
- `proposal-counter` → Buyout proposals counter.
- `gov-proposal-counter` → Governance proposals counter.
- `valuation-counter` → Valuation events counter.
- `platform-fee` → Fee charged on trades (default: 2%).

---

## ⚙️ Core Functions

### Administrative
- `set-platform-parameters` → Update fee, min/max fractions.

### NFT Management
- `mint-original-nft` → Mint a new NFT with metadata.
- `fractionalize-nft` → Convert NFT into fungible fractions.

### Marketplace
- `list-fractions-for-sale` → List fractions on the marketplace.
- `buy-from-listing` → Purchase fractions from an active listing.

### Buyouts
- `propose-buyout` → Propose a full buyout of a fractionalized NFT.
- `vote-on-buyout` → Fraction holders vote on proposals.
- `execute-buyout` → Execute an approved buyout and distribute proceeds.

### Revenue
- `distribute-revenue` → Add external revenue for distribution.
- `claim-revenue` → Claim fraction holder’s share of revenue.

### Read-only Queries
- `get-nft-metadata`  
- `get-fractionalization-info`  
- `get-fraction-balance`  
- `get-listing`  
- `get-buyout-proposal`  
- `get-revenue-pool`  
- `get-revenue-claims`  
- `get-valuation-history`  
- `get-contract-info`  

---

## 🔒 Security & Safeguards

- Only NFT owner can fractionalize their NFT.
- Min/max fractions enforced.
- Platform fee capped at 10%.
- All STX transfers use `try!` for safe failure handling.
- Buyout proposals require fraction threshold approval.
- Revenue and buyout proceeds tracked in pools before claims.

---

## 📊 Example Workflow

1. **Mint NFT**  
   `mint-original-nft` → Creates a new NFT.

2. **Fractionalize NFT**  
   `fractionalize-nft` → Locks NFT in vault and issues fractions.

3. **List Fractions**  
   `list-fractions-for-sale` → Owner lists fractions for sale.

4. **Trade Fractions**  
   `buy-from-listing` → Buyers purchase fractions.

5. **Revenue Distribution**  
   `distribute-revenue` → Add revenue for fraction holders.  
   `claim-revenue` → Holders claim their share.

6. **Buyout Proposal**  
   `propose-buyout` → New owner proposes full acquisition.  
   `vote-on-buyout` → Fraction holders vote.  
   `execute-buyout` → Approved buyout distributes proceeds and transfers NFT.

---

## 🛠 Development

- **Language:** Clarity  
- **Blockchain:** Stacks  
- **Token Standards:**  
  - `define-non-fungible-token` (NFTs)  
  - `define-fungible-token` (fractions)
