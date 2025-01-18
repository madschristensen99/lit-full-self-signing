// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../script/DeployPKPToolRegistry.s.sol";
import "../../src/PKPToolRegistry.sol";
import "../../src/facets/PKPToolRegistryToolFacet.sol";
import "../../src/facets/PKPToolRegistryPolicyFacet.sol";
import "../../src/facets/PKPToolRegistryDelegateeFacet.sol";
import "../../src/facets/PKPToolRegistryBlanketParameterFacet.sol";
import "../../src/facets/PKPToolRegistryPolicyParameterFacet.sol";
import "../../src/libraries/PKPToolRegistryErrors.sol";
import "../../src/libraries/PKPToolRegistryParameterEvents.sol";
import "../mocks/MockPKPNFT.sol";

contract PKPToolRegistryLifecycleTest is Test {
    // Test addresses
    MockPKPNFT mockPkpNft;
    address deployer;
    address nonOwner;
    
    // Contract instances
    PKPToolRegistry diamond;
    DeployPKPToolRegistry deployScript;
    
    // Test data
    uint256 constant TEST_PKP_TOKEN_ID = 1;
    address constant TEST_DELEGATEE = address(0x1234);
    address constant TEST_DELEGATEE_2 = address(0x5678);
    string constant TEST_TOOL_CID = "QmTEST";
    string constant TEST_TOOL_CID_2 = "QmTEST2";
    string constant TEST_POLICY_CID = "QmPOLICY";
    string constant TEST_POLICY_CID_2 = "QmPOLICY2";
    string constant TEST_PARAM_NAME = "maxAmount";
    string constant TEST_PARAM_NAME_2 = "minAmount";
    bytes constant TEST_PARAM_VALUE = abi.encode(1000);
    bytes constant TEST_PARAM_VALUE_2 = abi.encode(100);

    function setUp() public {
        // Setup deployer account using default test account
        deployer = vm.addr(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
        nonOwner = makeAddr("non-owner");

        // Deploy mock PKP NFT contract
        mockPkpNft = new MockPKPNFT();

        // Set environment variables for deployment
        vm.setEnv("PKP_TOOL_REGISTRY_DEPLOYER_PRIVATE_KEY", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
        
        // Deploy using the script
        deployScript = new DeployPKPToolRegistry();
        address diamondAddress = deployScript.deployToNetwork("test", address(mockPkpNft));
        diamond = PKPToolRegistry(payable(diamondAddress));

        // Set up mock PKP NFT for tests
        mockPkpNft.setOwner(TEST_PKP_TOKEN_ID, deployer);
    }

    /// @notice Test full lifecycle of PKP Tool Registry interactions
    function test_fullLifecycle() public {
        vm.startPrank(deployer);

        // Step 1: Register multiple tools
        string[] memory toolIpfsCids = new string[](2);
        toolIpfsCids[0] = TEST_TOOL_CID;
        toolIpfsCids[1] = TEST_TOOL_CID_2;
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids, true);

        // Verify tools are registered and enabled
        string[] memory registeredTools = PKPToolRegistryToolFacet(address(diamond)).getRegisteredTools(TEST_PKP_TOKEN_ID);
        assertEq(registeredTools.length, 2, "Wrong number of registered tools");
        
        (bool isRegistered1, bool isEnabled1) = PKPToolRegistryToolFacet(address(diamond)).isToolRegistered(TEST_PKP_TOKEN_ID, TEST_TOOL_CID);
        (bool isRegistered2, bool isEnabled2) = PKPToolRegistryToolFacet(address(diamond)).isToolRegistered(TEST_PKP_TOKEN_ID, TEST_TOOL_CID_2);
        assertTrue(isRegistered1 && isEnabled1, "Tool 1 should be registered and enabled");
        assertTrue(isRegistered2 && isEnabled2, "Tool 2 should be registered and enabled");

        // Step 2: Add delegatees
        address[] memory delegatees = new address[](2);
        delegatees[0] = TEST_DELEGATEE;
        delegatees[1] = TEST_DELEGATEE_2;
        PKPToolRegistryDelegateeFacet(address(diamond)).addDelegatees(TEST_PKP_TOKEN_ID, delegatees);

        // Verify delegatees are added with individual checks
        address[] memory storedDelegatees = PKPToolRegistryDelegateeFacet(address(diamond)).getDelegatees(TEST_PKP_TOKEN_ID);
        assertEq(storedDelegatees.length, 2, "Wrong number of delegatees");
        bool isDelegatee1 = PKPToolRegistryDelegateeFacet(address(diamond)).isPkpDelegatee(TEST_PKP_TOKEN_ID, TEST_DELEGATEE);
        bool isDelegatee2 = PKPToolRegistryDelegateeFacet(address(diamond)).isPkpDelegatee(TEST_PKP_TOKEN_ID, TEST_DELEGATEE_2);
        assertTrue(isDelegatee1, "First delegatee should be added");
        assertTrue(isDelegatee2, "Second delegatee should be added");

        // Step 3: Set blanket policies for tools
        string[] memory policyIpfsCids = new string[](2);
        policyIpfsCids[0] = TEST_POLICY_CID;
        policyIpfsCids[1] = TEST_POLICY_CID_2;
        PKPToolRegistryBlanketPolicyFacet(address(diamond)).setBlanketToolPolicies(TEST_PKP_TOKEN_ID, toolIpfsCids, policyIpfsCids, true);

        // Verify blanket policies are set
        string memory blanketPolicy1 = PKPToolRegistryBlanketPolicyFacet(address(diamond)).getBlanketToolPolicy(TEST_PKP_TOKEN_ID, TEST_TOOL_CID);
        string memory blanketPolicy2 = PKPToolRegistryBlanketPolicyFacet(address(diamond)).getBlanketToolPolicy(TEST_PKP_TOKEN_ID, TEST_TOOL_CID_2);
        assertEq(blanketPolicy1, TEST_POLICY_CID, "Wrong blanket policy for tool 1");
        assertEq(blanketPolicy2, TEST_POLICY_CID_2, "Wrong blanket policy for tool 2");

        // Step 4: Set blanket parameters for tools
        string[] memory parameterNames = new string[](2);
        parameterNames[0] = TEST_PARAM_NAME;
        parameterNames[1] = TEST_PARAM_NAME_2;
        bytes[] memory parameterValues = new bytes[](2);
        parameterValues[0] = TEST_PARAM_VALUE;
        parameterValues[1] = TEST_PARAM_VALUE_2;

        PKPToolRegistryBlanketParameterFacet(address(diamond)).setBlanketToolPolicyParameters(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            parameterNames,
            parameterValues
        );

        // Verify blanket parameters are set
        string[] memory storedParamNames = PKPToolRegistryBlanketParameterFacet(address(diamond)).getBlanketToolPolicyParameterNames(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID
        );
        assertEq(storedParamNames.length, 2, "Wrong number of blanket parameters");
        bytes[] memory storedParamValues = PKPToolRegistryBlanketParameterFacet(address(diamond)).getBlanketToolPolicyParameters(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            parameterNames
        );
        assertEq(storedParamValues[0], TEST_PARAM_VALUE, "Wrong blanket parameter value 1");
        assertEq(storedParamValues[1], TEST_PARAM_VALUE_2, "Wrong blanket parameter value 2");

        // Step 5: Set delegatee-specific policies
        string[] memory singleToolArray = new string[](1);
        singleToolArray[0] = TEST_TOOL_CID;
        address[] memory singleDelegateeArray = new address[](1);
        singleDelegateeArray[0] = TEST_DELEGATEE;
        string[] memory delegateePolicies = new string[](1);
        delegateePolicies[0] = TEST_POLICY_CID_2;
        PKPToolRegistryPolicyFacet(address(diamond)).setCustomToolPoliciesForDelegatees(
            TEST_PKP_TOKEN_ID,
            singleToolArray,
            singleDelegateeArray,
            delegateePolicies,
            true
        );

        // Verify delegatee-specific policy is set
        string memory delegateePolicy = PKPToolRegistryPolicyFacet(address(diamond)).getCustomToolPolicyForDelegatee(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            TEST_DELEGATEE
        );
        assertEq(delegateePolicy, TEST_POLICY_CID_2, "Wrong delegatee policy");

        // Step 6: Set delegatee-specific parameters
        PKPToolRegistryPolicyParameterFacet(address(diamond)).setToolPolicyParametersForDelegatee(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            TEST_DELEGATEE,
            parameterNames,
            parameterValues
        );

        // Verify delegatee-specific parameters are set
        storedParamNames = PKPToolRegistryPolicyParameterFacet(address(diamond)).getToolPolicyParameterNamesForDelegatee(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            TEST_DELEGATEE
        );
        assertEq(storedParamNames.length, 2, "Wrong number of delegatee parameters");
        storedParamValues = PKPToolRegistryPolicyParameterFacet(address(diamond)).getToolPolicyParametersForDelegatee(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            TEST_DELEGATEE,
            parameterNames
        );
        assertEq(storedParamValues[0], TEST_PARAM_VALUE, "Wrong delegatee parameter value 1");
        assertEq(storedParamValues[1], TEST_PARAM_VALUE_2, "Wrong delegatee parameter value 2");

        // Step 7: Disable some policies and parameters
        PKPToolRegistryBlanketPolicyFacet(address(diamond)).disableBlanketPolicies(TEST_PKP_TOKEN_ID, toolIpfsCids);
        PKPToolRegistryPolicyFacet(address(diamond)).disableCustomToolPoliciesForDelegatees(
            TEST_PKP_TOKEN_ID,
            singleToolArray,
            singleDelegateeArray
        );

        // Verify policies are disabled
        blanketPolicy1 = PKPToolRegistryBlanketPolicyFacet(address(diamond)).getBlanketToolPolicy(TEST_PKP_TOKEN_ID, TEST_TOOL_CID);
        blanketPolicy2 = PKPToolRegistryBlanketPolicyFacet(address(diamond)).getBlanketToolPolicy(TEST_PKP_TOKEN_ID, TEST_TOOL_CID_2);
        assertEq(blanketPolicy1, "", "First blanket policy should be disabled");
        assertEq(blanketPolicy2, "", "Second blanket policy should be disabled");
        
        delegateePolicy = PKPToolRegistryPolicyFacet(address(diamond)).getCustomToolPolicyForDelegatee(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            TEST_DELEGATEE
        );
        assertEq(delegateePolicy, "", "Delegatee policy should be disabled");

        // Step 8: Remove some policies and parameters
        string[] memory paramsToRemove = new string[](1);
        paramsToRemove[0] = TEST_PARAM_NAME;
        PKPToolRegistryBlanketParameterFacet(address(diamond)).removeBlanketToolPolicyParameters(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            paramsToRemove
        );
        PKPToolRegistryPolicyParameterFacet(address(diamond)).removeToolPolicyParametersForDelegatee(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            TEST_DELEGATEE,
            paramsToRemove
        );

        // Verify parameters are removed
        storedParamNames = PKPToolRegistryBlanketParameterFacet(address(diamond)).getBlanketToolPolicyParameterNames(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID
        );
        assertEq(storedParamNames.length, 1, "Should have 1 blanket parameter remaining");
        storedParamNames = PKPToolRegistryPolicyParameterFacet(address(diamond)).getToolPolicyParameterNamesForDelegatee(
            TEST_PKP_TOKEN_ID,
            TEST_TOOL_CID,
            TEST_DELEGATEE
        );
        assertEq(storedParamNames.length, 1, "Should have 1 delegatee parameter remaining");

        // Step 9: Remove delegatees
        PKPToolRegistryDelegateeFacet(address(diamond)).removeDelegatees(TEST_PKP_TOKEN_ID, delegatees);

        // Verify delegatees are removed
        storedDelegatees = PKPToolRegistryDelegateeFacet(address(diamond)).getDelegatees(TEST_PKP_TOKEN_ID);
        assertEq(storedDelegatees.length, 0, "All delegatees should be removed");

        // Step 10: Remove tools
        PKPToolRegistryToolFacet(address(diamond)).removeTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Verify tools are removed
        registeredTools = PKPToolRegistryToolFacet(address(diamond)).getRegisteredTools(TEST_PKP_TOKEN_ID);
        assertEq(registeredTools.length, 0, "All tools should be removed");

        vm.stopPrank();
    }
} 