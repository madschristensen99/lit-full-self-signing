declare global {
  // Injected By Lit
  const Lit: any;
  const LitAuth: any;
  const ethers: {
    providers: {
      JsonRpcProvider: any;
    };
    utils: {
      Interface: any;
      parseUnits: any;
      formatUnits: any;
      formatEther: any;
      arrayify: any;
      keccak256: any;
      serializeTransaction: any;
      joinSignature: any;
      isHexString: any;
      getAddress: any;
      defaultAbiCoder: any;
    };
    BigNumber: any;
    Contract: any;
  };

  // Injected by build script
  const LIT_NETWORK: string;
  const PKP_TOOL_REGISTRY_ADDRESS: string;

  // Required Inputs
  const params: {
    pkpEthAddress: string;
    rpcUrl: string;
    chainId: string;
    tokenIn: string;
    recipientAddress: string;
    amountIn: string;
  };
}

/**
 * Main function to execute the Lit Action.
 * Handles PKP info retrieval, input validation, gas estimation, transaction creation, and broadcasting.
 */
export default async () => {
  try {
    /**
     * Retrieves PKP information from the PubkeyRouter contract.
     * @returns {Promise<{ tokenId: string, ethAddress: string, publicKey: string }>} PKP information.
     */
    async function getPkpInfo() {
      console.log('Getting PKP info from PubkeyRouter...');

      // Get PubkeyRouter address for current network
      const networkConfig =
        NETWORK_CONFIG[LIT_NETWORK as keyof typeof NETWORK_CONFIG];
      if (!networkConfig) {
        throw new Error(`Unsupported Lit network: ${LIT_NETWORK}`);
      }

      const PUBKEY_ROUTER_ABI = [
        'function ethAddressToPkpId(address ethAddress) public view returns (uint256)',
        'function getPubkey(uint256 tokenId) public view returns (bytes memory)',
      ];

      const pubkeyRouter = new ethers.Contract(
        networkConfig.pubkeyRouterAddress,
        PUBKEY_ROUTER_ABI,
        new ethers.providers.JsonRpcProvider(
          await Lit.Actions.getRpcUrl({
            chain: 'yellowstone',
          })
        )
      );

      // Get PKP ID from eth address
      console.log(`Getting PKP ID for eth address ${params.pkpEthAddress}...`);
      const pkpTokenId = await pubkeyRouter.ethAddressToPkpId(
        params.pkpEthAddress
      );
      console.log(`Got PKP token ID: ${pkpTokenId}`);

      // Get public key from PKP ID
      console.log(`Getting public key for PKP ID ${pkpTokenId}...`);
      const publicKey = await pubkeyRouter.getPubkey(pkpTokenId);
      console.log(`Got public key: ${publicKey}`);

      return {
        tokenId: pkpTokenId.toString(),
        ethAddress: params.pkpEthAddress,
        publicKey,
      };
    }

    /**
     * Checks if the session signer is a delegatee for the PKP.
     * @param {any} pkpToolRegistryContract - The PKP Tool Registry contract instance.
     */
    async function checkLitAuthAddressIsDelegatee(
      pkpToolRegistryContract: any
    ) {
      console.log(
        `Checking if Lit Auth address: ${LitAuth.authSigAddress} is a delegatee for PKP ${pkp.tokenId}...`
      );

      // Check if the session signer is a delegatee
      const sessionSigner = ethers.utils.getAddress(LitAuth.authSigAddress);
      const isDelegatee = await pkpToolRegistryContract.isDelegateeOf(
        pkp.tokenId,
        sessionSigner
      );

      if (!isDelegatee) {
        throw new Error(
          `Session signer ${sessionSigner} is not a delegatee for PKP ${pkp.tokenId}`
        );
      }

      console.log(
        `Session signer ${sessionSigner} is a delegatee for PKP ${pkp.tokenId}`
      );
    }

    /**
     * Validates inputs against the policy defined in the PKP Tool Registry.
     * @param {any} pkpToolRegistryContract - The PKP Tool Registry contract instance.
     * @param {any} amount - The amount to validate.
     */
    async function validateInputsAgainstPolicy(
      pkpToolRegistryContract: any,
      amount: any
    ) {
      console.log(`Validating inputs against policy...`);

      // Get policy for this tool
      const TOOL_IPFS_CID = LitAuth.actionIpfsIds[0];
      console.log(`Getting policy for tool ${TOOL_IPFS_CID}...`);
      const [policyData] = await pkpToolRegistryContract.getToolPolicy(
        pkp.tokenId,
        TOOL_IPFS_CID
      );

      if (policyData === '0x') {
        console.log(
          `No policy found for tool ${TOOL_IPFS_CID} on PKP ${pkp.tokenId}`
        );
        return;
      }

      // Decode policy
      console.log(`Decoding policy...`);
      const decodedPolicy = ethers.utils.defaultAbiCoder.decode(
        [
          'tuple(uint8 erc20Decimals, uint256 maxAmount, address[] allowedTokens, address[] allowedRecipients)',
        ],
        policyData
      )[0];

      // Validate amount
      if (amount.gt(decodedPolicy.maxAmount)) {
        throw new Error(
          `Amount exceeds policy limit. Max allowed: ${ethers.utils.formatEther(
            decodedPolicy.maxAmount
          )} ETH`
        );
      }

      // Validate token
      if (
        decodedPolicy.allowedTokens.length > 0 &&
        !decodedPolicy.allowedTokens
          .map((addr: string) => ethers.utils.getAddress(addr))
          .includes(ethers.utils.getAddress(params.tokenIn))
      ) {
        throw new Error(
          `Token ${
            params.tokenIn
          } not allowed. Allowed tokens: ${decodedPolicy.allowedTokens.join(
            ', '
          )}`
        );
      }

      // Validate recipient
      if (
        decodedPolicy.allowedRecipients.length > 0 &&
        !decodedPolicy.allowedRecipients
          .map((addr: string) => ethers.utils.getAddress(addr))
          .includes(ethers.utils.getAddress(params.recipientAddress))
      ) {
        throw new Error(
          `Recipient ${
            params.recipientAddress
          } not allowed. Allowed recipients: ${decodedPolicy.allowedRecipients.join(
            ', '
          )}`
        );
      }

      console.log(`Inputs validated against policy`);
    }

    /**
     * Retrieves token information (decimals, balance, and parsed amount).
     * @param {any} provider - The Ethereum provider.
     * @returns {Promise<{ decimals: number, balance: any, amount: any }>} Token information.
     */
    async function getTokenInfo(provider: any) {
      console.log('Getting token info for:', params.tokenIn);

      // Validate token address
      try {
        ethers.utils.getAddress(params.tokenIn);
      } catch (error) {
        throw new Error(`Invalid token address: ${params.tokenIn}`);
      }

      // Check if contract exists
      const code = await provider.getCode(params.tokenIn);
      if (code === '0x') {
        throw new Error(`No contract found at address: ${params.tokenIn}`);
      }

      const tokenInterface = new ethers.utils.Interface([
        'function decimals() view returns (uint8)',
        'function balanceOf(address account) view returns (uint256)',
        'function transfer(address to, uint256 amount) external returns (bool)',
      ]);

      console.log('Creating token contract instance...');
      const tokenContract = new ethers.Contract(
        params.tokenIn,
        tokenInterface,
        provider
      );

      console.log('Fetching token decimals and balance...');
      try {
        const decimals = await tokenContract.decimals();
        console.log('Token decimals:', decimals);

        const balance = await tokenContract.balanceOf(pkp.ethAddress);
        console.log('Token balance:', balance.toString());

        const amount = ethers.utils.parseUnits(params.amountIn, decimals);
        console.log('Amount to send:', amount.toString());

        if (amount.gt(balance)) {
          throw new Error(
            `Insufficient balance. PKP balance: ${ethers.utils.formatUnits(
              balance,
              decimals
            )}. Required: ${ethers.utils.formatUnits(amount, decimals)}`
          );
        }

        return { decimals, balance, amount };
      } catch (error) {
        console.error('Error getting token info:', error);
        throw new Error(
          `Failed to interact with token contract at ${params.tokenIn}. Make sure this is a valid ERC20 token contract.`
        );
      }
    }

    /**
     * Retrieves gas data (maxFeePerGas, maxPriorityFeePerGas, and nonce).
     * @returns {Promise<{ maxFeePerGas: string, maxPriorityFeePerGas: string, nonce: number }>} Gas data.
     */
    async function getGasData() {
      console.log(`Getting gas data...`);

      const gasData = await Lit.Actions.runOnce(
        { waitForResponse: true, name: 'gasPriceGetter' },
        async () => {
          const provider = new ethers.providers.JsonRpcProvider(params.rpcUrl);
          const baseFeeHistory = await provider.send('eth_feeHistory', [
            '0x1',
            'latest',
            [],
          ]);
          const baseFee = ethers.BigNumber.from(
            baseFeeHistory.baseFeePerGas[0]
          );
          const nonce = await provider.getTransactionCount(pkp.ethAddress);

          const priorityFee = baseFee.div(4);
          const maxFee = baseFee.mul(2);

          return JSON.stringify({
            maxFeePerGas: maxFee.toHexString(),
            maxPriorityFeePerGas: priorityFee.toHexString(),
            nonce,
          });
        }
      );

      console.log(`Gas data: ${gasData}`);

      return JSON.parse(gasData);
    }

    /**
     * Estimates the gas limit for the transaction.
     * @param {any} provider - The Ethereum provider.
     * @param {any} amount - The amount to transfer.
     * @returns {Promise<any>} Estimated gas limit.
     */
    async function estimateGasLimit(provider: any, amount: any) {
      console.log(`Estimating gas limit...`);

      const tokenInterface = new ethers.utils.Interface([
        'function transfer(address to, uint256 amount) external returns (bool)',
      ]);

      const tokenContract = new ethers.Contract(
        params.tokenIn,
        tokenInterface,
        provider
      );

      try {
        const estimatedGas = await tokenContract.estimateGas.transfer(
          params.recipientAddress,
          amount,
          { from: pkp.ethAddress }
        );
        console.log('Estimated gas limit:', estimatedGas.toString());
        return estimatedGas.mul(120).div(100);
      } catch (error) {
        console.error(
          'Could not estimate gas. Using fallback gas limit of 100000.',
          error
        );
        return ethers.BigNumber.from('100000');
      }
    }

    /**
     * Creates and signs the transaction.
     * @param {any} gasLimit - The gas limit for the transaction.
     * @param {any} amount - The amount to transfer.
     * @param {any} gasData - Gas data (maxFeePerGas, maxPriorityFeePerGas, nonce).
     * @returns {Promise<string>} The signed transaction.
     */
    async function createAndSignTransaction(
      gasLimit: any,
      amount: any,
      gasData: any
    ) {
      console.log(`Creating and signing transaction...`);

      const tokenInterface = new ethers.utils.Interface([
        'function transfer(address to, uint256 amount) external returns (bool)',
      ]);

      const transferTx = {
        to: params.tokenIn,
        data: tokenInterface.encodeFunctionData('transfer', [
          params.recipientAddress,
          amount,
        ]),
        value: '0x0',
        gasLimit: gasLimit.toHexString(),
        maxFeePerGas: gasData.maxFeePerGas,
        maxPriorityFeePerGas: gasData.maxPriorityFeePerGas,
        nonce: gasData.nonce,
        chainId: params.chainId,
        type: 2,
      };

      console.log(`Signing transfer with PKP public key: ${pkp.publicKey}...`);
      const transferSig = await Lit.Actions.signAndCombineEcdsa({
        toSign: ethers.utils.arrayify(
          ethers.utils.keccak256(ethers.utils.serializeTransaction(transferTx))
        ),
        publicKey: pkp.publicKey.startsWith('0x')
          ? pkp.publicKey.slice(2)
          : pkp.publicKey,
        sigName: 'erc20TransferSig',
      });

      console.log(`Transaction signed`);

      return ethers.utils.serializeTransaction(
        transferTx,
        ethers.utils.joinSignature({
          r: '0x' + JSON.parse(transferSig).r.substring(2),
          s: '0x' + JSON.parse(transferSig).s,
          v: JSON.parse(transferSig).v,
        })
      );
    }

    /**
     * Broadcasts the signed transaction to the network.
     * @param {string} signedTx - The signed transaction.
     * @returns {Promise<string>} The transaction hash.
     */
    async function broadcastTransaction(signedTx: string) {
      console.log('Broadcasting transfer...');
      return await Lit.Actions.runOnce(
        { waitForResponse: true, name: 'txnSender' },
        async () => {
          try {
            const provider = new ethers.providers.JsonRpcProvider(
              params.rpcUrl
            );
            const tx = await provider.sendTransaction(signedTx);
            console.log('Transaction sent:', tx.hash);

            const receipt = await tx.wait(1);
            console.log('Transaction mined:', receipt.transactionHash);

            return receipt.transactionHash;
          } catch (err: any) {
            // Log the full error object for debugging
            console.error('Full error object:', JSON.stringify(err, null, 2));

            // Extract detailed error information
            const errorDetails = {
              message: err.message,
              code: err.code,
              reason: err.reason,
              error: err.error,
              ...(err.transaction && { transaction: err.transaction }),
              ...(err.receipt && { receipt: err.receipt }),
            };

            console.error(
              'Error details:',
              JSON.stringify(errorDetails, null, 2)
            );

            // Return stringified error response
            return JSON.stringify({
              error: true,
              message: err.reason || err.message || 'Transaction failed',
              details: errorDetails,
            });
          }
        }
      );
    }

    // Main Execution
    // Network to PubkeyRouter address mapping
    const NETWORK_CONFIG = {
      'datil-dev': {
        pubkeyRouterAddress: '0xbc01f21C58Ca83f25b09338401D53D4c2344D1d9',
      },
      'datil-test': {
        pubkeyRouterAddress: '0x65C3d057aef28175AfaC61a74cc6b27E88405583',
      },
      datil: {
        pubkeyRouterAddress: '0xF182d6bEf16Ba77e69372dD096D8B70Bc3d5B475',
      },
    } as const;

    console.log(`Using Lit Network: ${LIT_NETWORK}`);
    console.log(
      `Using PKP Tool Registry Address: ${PKP_TOOL_REGISTRY_ADDRESS}`
    );
    console.log(
      `Using Pubkey Router Address: ${
        NETWORK_CONFIG[LIT_NETWORK as keyof typeof NETWORK_CONFIG]
          .pubkeyRouterAddress
      }`
    );

    const pkp = await getPkpInfo();
    const provider = new ethers.providers.JsonRpcProvider(params.rpcUrl);
    const tokenInfo = await getTokenInfo(provider);

    // Create contract instance
    const PKP_TOOL_REGISTRY_ABI = [
      'function isDelegateeOf(uint256 pkpTokenId, address delegatee) external view returns (bool)',
      'function getToolPolicy(uint256 pkpTokenId, string calldata ipfsCid) external view returns (bytes memory policy, string memory version)',
    ];
    const pkpToolRegistryContract = new ethers.Contract(
      PKP_TOOL_REGISTRY_ADDRESS,
      PKP_TOOL_REGISTRY_ABI,
      new ethers.providers.JsonRpcProvider(
        await Lit.Actions.getRpcUrl({
          chain: 'yellowstone',
        })
      )
    );

    await checkLitAuthAddressIsDelegatee(pkpToolRegistryContract);
    await validateInputsAgainstPolicy(
      pkpToolRegistryContract,
      tokenInfo.amount
    );

    const gasData = await getGasData();
    const gasLimit = await estimateGasLimit(provider, tokenInfo.amount);
    const signedTx = await createAndSignTransaction(
      gasLimit,
      tokenInfo.amount,
      gasData
    );
    const result = await broadcastTransaction(signedTx);

    console.log('Result:', result);

    // Try to parse the result
    let parsedResult;
    try {
      parsedResult = JSON.parse(result);
    } catch {
      // If it's not JSON, assume it's a transaction hash
      parsedResult = result;
    }

    // Check if result is an error object
    if (typeof parsedResult === 'object' && parsedResult.error) {
      throw new Error(parsedResult.message);
    }

    // At this point, result should be a transaction hash
    if (!parsedResult) {
      throw new Error('Transaction failed: No transaction hash returned');
    }

    if (!ethers.utils.isHexString(parsedResult)) {
      throw new Error(
        `Transaction failed: Invalid transaction hash format. Received: ${JSON.stringify(
          parsedResult
        )}`
      );
    }

    Lit.Actions.setResponse({
      response: JSON.stringify({
        status: 'success',
        transferHash: parsedResult,
      }),
    });
  } catch (err: any) {
    console.error('Error:', err);

    // Extract detailed error information
    const errorDetails = {
      message: err.message,
      code: err.code,
      reason: err.reason,
      error: err.error,
      ...(err.transaction && { transaction: err.transaction }),
      ...(err.receipt && { receipt: err.receipt }),
    };

    // Construct a detailed error message
    const errorMessage = err.message || String(err);

    Lit.Actions.setResponse({
      response: JSON.stringify({
        status: 'error',
        error: errorMessage,
        details: errorDetails,
      }),
    });
  }
};
