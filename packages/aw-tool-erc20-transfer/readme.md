# AW-Tool Uniswap Swap Documentation

The `aw-tool-uniswap-swap` folder contains utilities for interacting with Uniswap swaps using Lit Protocol and Ethereum.

---

## Files Overview

### 1. **`ipfs.ts`**
Handles IPFS CIDs for different environments (development, testing, production). Falls back to default CIDs if the build output is not found.

#### Key Features:
- **Default CIDs**: Predefined CIDs for `datil-dev`, `datil-test`, and `datil` environments.
- **Dynamic CID Loading**: Attempts to load CIDs from `dist/ipfs.json` at runtime.
- **Fallback Mechanism**: Uses default CIDs if the file is missing or unreadable.

---

### 2. **`lit-action.ts`**
Contains the main logic for executing a Lit Action to perform an ERC20 token transfer.

#### Key Features:
- **PKP Info Retrieval**: Fetches PKP details (token ID, Ethereum address, public key) from the PubkeyRouter contract.
- **Input Validation**: Validates inputs against the policy defined in the PKP Tool Registry.
- **Gas Estimation**: Estimates gas limits and fees for the transaction.
- **Transaction Creation**: Creates and signs the transaction using the PKP public key.
- **Broadcasting**: Sends the signed transaction to the network.

---

### 3. **`policy.ts`**
Defines and validates the ERC20 transfer policy schema using Zod.

#### Key Features:
- **Policy Schema**: Validates policy fields like `erc20Decimals`, `maxAmount`, `allowedTokens`, and `allowedRecipients`.
- **Encoding/Decoding**: Converts policies to and from ABI-encoded strings.
- **Type Safety**: Uses Zod for robust validation and TypeScript for type inference.

---

### 4. **`tool.ts`**
Configures the ERC20 transfer tool for different Lit networks.

#### Key Features:
- **Parameter Validation**: Validates inputs like `pkpEthAddress`, `tokenIn`, `recipientAddress`, and `amountIn`.
- **Network-Specific Tools**: Creates tools for `datil-dev`, `datil-test`, and `datil` environments.
- **Policy Integration**: Integrates with the `ERC20TransferPolicy` for policy handling.

---

## Usage Example

### 1. **Set Up the Tool**
```typescript
import { ERC20Transfer } from './tool';

const tool = ERC20Transfer['datil-dev'];

const params = {
  pkpEthAddress: '0x...',
  tokenIn: '0x...',
  recipientAddress: '0x...',
  amountIn: '100',
  chainId: '1',
  rpcUrl: 'https://mainnet.infura.io/v3/...',
};

const validationResult = tool.parameters.validate(params);
if (validationResult !== true) {
  console.error('Validation errors:', validationResult);
}

const result = await tool.execute(params);
console.log('Transaction hash:', result.transferHash);