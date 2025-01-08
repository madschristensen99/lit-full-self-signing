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
      defaultAbiCoder: any;
      keccak256: any;
      toUtf8Bytes: any;
      arrayify: any;
      getAddress: any;
    };
    Wallet: any;
    Contract: any;
  };

  // Injected by build script
  const LIT_NETWORK: string;
  const PKP_TOOL_REGISTRY_ADDRESS: string;

  // Required Inputs
  const params: {
    pkpEthAddress: string;
    message: string;
  };
}

export default async () => {
  try {
    // Get PKP info from PubkeyRouter
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

      // TODO Implement this check
      // if (pkpTokenId.isZero()) {
      //   throw new Error(`No PKP found for eth address ${params.pkpEthAddress}`);
      // }

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

    async function validateInputsAgainstPolicy(pkpToolRegistryContract: any) {
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
        ['tuple(string[] allowedPrefixes)'],
        policyData
      )[0];

      // Validate message prefix
      if (
        !decodedPolicy.allowedPrefixes.some((prefix: string) =>
          params.message.startsWith(prefix)
        )
      ) {
        throw new Error(
          `Message does not start with any allowed prefix. Allowed prefixes: ${decodedPolicy.allowedPrefixes.join(
            ', '
          )}`
        );
      }

      console.log(`Inputs validated against policy`);
    }

    async function signMessage(message: string) {
      const pkForLit = pkp.publicKey.startsWith('0x')
        ? pkp.publicKey.slice(2)
        : pkp.publicKey;

      const sig = await Lit.Actions.signEcdsa({
        toSign: ethers.utils.arrayify(
          ethers.utils.keccak256(ethers.utils.toUtf8Bytes(message))
        ),
        publicKey: pkForLit,
        sigName: 'sig',
      });

      return sig;
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

    const PKP_TOOL_REGISTRY_ABI = [
      'function isDelegateeOf(uint256 pkpTokenId, address delegatee) external view returns (bool)',
      'function getToolPolicy(uint256 pkpTokenId, string calldata ipfsCid) external view returns (bytes memory policy, string memory version)',
    ];
    const PKP_TOOL_REGISTRY = '0xb8000069FeD07794c23Fc1622F02fe54788Dae3F';
    const pkpToolRegistryContract = new ethers.Contract(
      PKP_TOOL_REGISTRY,
      PKP_TOOL_REGISTRY_ABI,
      new ethers.providers.JsonRpcProvider(
        await Lit.Actions.getRpcUrl({
          chain: 'yellowstone',
        })
      )
    );

    await checkLitAuthAddressIsDelegatee(pkpToolRegistryContract);
    await validateInputsAgainstPolicy(pkpToolRegistryContract);

    await signMessage(params.message);

    // Return the signature
    Lit.Actions.setResponse({
      response: JSON.stringify({
        response: 'Signed message!',
        status: 'success',
      }),
    });
  } catch (err: any) {
    console.error('Error:', err);
    Lit.Actions.setResponse({
      response: JSON.stringify({
        status: 'error',
        error: err.message || String(err),
      }),
    });
  }
};