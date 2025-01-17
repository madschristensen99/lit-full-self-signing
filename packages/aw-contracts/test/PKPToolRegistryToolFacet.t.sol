// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../script/DeployPKPToolRegistry.s.sol";
import "../src/PKPToolRegistry.sol";
import "../src/facets/PKPToolRegistryToolFacet.sol";
import "../src/libraries/PKPToolRegistryErrors.sol";
import "../src/libraries/PKPToolRegistryToolEvents.sol";
import "./mocks/MockPKPNFT.sol";

contract PKPToolRegistryToolFacetTest is Test {
    // Test addresses
    MockPKPNFT mockPkpNft;
    address deployer;
    address nonOwner;
    
    // Contract instances
    PKPToolRegistry diamond;
    DeployPKPToolRegistry deployScript;
    
    // Test data
    uint256 constant TEST_PKP_TOKEN_ID = 1;
    string constant TEST_TOOL_CID = "test-tool-cid";
    string constant TEST_TOOL_CID_2 = "test-tool-cid-2";

    // Events to test
    event ToolsRegistered(uint256 indexed pkpTokenId, string[] toolIpfsCids);
    event ToolsRemoved(uint256 indexed pkpTokenId, string[] toolIpfsCids);
    event ToolsEnabled(uint256 indexed pkpTokenId, string[] toolIpfsCids);
    event ToolsDisabled(uint256 indexed pkpTokenId, string[] toolIpfsCids);

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

    /// @notice Test registering a single tool
    function test_registerSingleTool() public {
        vm.startPrank(deployer);

        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = TEST_TOOL_CID;

        // Expect the ToolsRegistered event
        vm.expectEmit(true, false, false, true);
        emit ToolsRegistered(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Register the tool
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Verify registration
        string[] memory registeredTools = PKPToolRegistryToolFacet(address(diamond)).getRegisteredTools(TEST_PKP_TOKEN_ID);
        assertEq(registeredTools.length, 1, "Wrong number of registered tools");
        assertEq(registeredTools[0], TEST_TOOL_CID, "Wrong tool CID registered");

        vm.stopPrank();
    }

    /// @notice Test registering multiple tools
    function test_registerMultipleTools() public {
        vm.startPrank(deployer);

        string[] memory toolIpfsCids = new string[](2);
        toolIpfsCids[0] = TEST_TOOL_CID;
        toolIpfsCids[1] = TEST_TOOL_CID_2;

        // Expect the ToolsRegistered event
        vm.expectEmit(true, false, false, true);
        emit ToolsRegistered(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Register the tools
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Verify registration
        string[] memory registeredTools = PKPToolRegistryToolFacet(address(diamond)).getRegisteredTools(TEST_PKP_TOKEN_ID);
        assertEq(registeredTools.length, 2, "Wrong number of registered tools");
        assertEq(registeredTools[0], TEST_TOOL_CID, "Wrong first tool CID registered");
        assertEq(registeredTools[1], TEST_TOOL_CID_2, "Wrong second tool CID registered");

        vm.stopPrank();
    }

    /// @notice Test registering with empty IPFS CID
    function test_registerEmptyIPFSCID() public {
        vm.startPrank(deployer);

        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = ""; // Empty CID

        vm.expectRevert(PKPToolRegistryErrors.EmptyIPFSCID.selector);
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        vm.stopPrank();
    }

    /// @notice Test registering duplicate tool
    function test_registerDuplicateTool() public {
        vm.startPrank(deployer);

        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = TEST_TOOL_CID;

        // Register first time
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Try to register same tool again
        vm.expectRevert(abi.encodeWithSelector(PKPToolRegistryErrors.ToolAlreadyExists.selector, TEST_TOOL_CID));
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        vm.stopPrank();
    }

    /// @notice Test non-owner registration attempt
    function test_registerNonOwner() public {
        vm.startPrank(nonOwner);

        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = TEST_TOOL_CID;

        vm.expectRevert(PKPToolRegistryErrors.NotPKPOwner.selector);
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        vm.stopPrank();
    }

    /// @notice Test removing a single tool
    function test_removeSingleTool() public {
        vm.startPrank(deployer);

        // First register a tool
        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = TEST_TOOL_CID;
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Expect the ToolsRemoved event
        vm.expectEmit(true, false, false, true);
        emit ToolsRemoved(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Remove the tool
        PKPToolRegistryToolFacet(address(diamond)).removeTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Verify removal
        string[] memory registeredTools = PKPToolRegistryToolFacet(address(diamond)).getRegisteredTools(TEST_PKP_TOKEN_ID);
        assertEq(registeredTools.length, 0, "Tool was not removed");

        vm.stopPrank();
    }

    /// @notice Test removing multiple tools
    function test_removeMultipleTools() public {
        vm.startPrank(deployer);

        // First register multiple tools
        string[] memory toolIpfsCids = new string[](2);
        toolIpfsCids[0] = TEST_TOOL_CID;
        toolIpfsCids[1] = TEST_TOOL_CID_2;
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Expect the ToolsRemoved event
        vm.expectEmit(true, false, false, true);
        emit ToolsRemoved(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Remove the tools
        PKPToolRegistryToolFacet(address(diamond)).removeTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Verify removal
        string[] memory registeredTools = PKPToolRegistryToolFacet(address(diamond)).getRegisteredTools(TEST_PKP_TOKEN_ID);
        assertEq(registeredTools.length, 0, "Tools were not removed");

        vm.stopPrank();
    }

    /// @notice Test removing with empty IPFS CID
    function test_removeEmptyIPFSCID() public {
        vm.startPrank(deployer);

        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = ""; // Empty CID

        vm.expectRevert(PKPToolRegistryErrors.EmptyIPFSCID.selector);
        PKPToolRegistryToolFacet(address(diamond)).removeTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        vm.stopPrank();
    }

    /// @notice Test removing non-existent tool
    function test_removeNonExistentTool() public {
        vm.startPrank(deployer);

        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = TEST_TOOL_CID;

        vm.expectRevert(abi.encodeWithSelector(PKPToolRegistryErrors.ToolNotFound.selector, TEST_TOOL_CID));
        PKPToolRegistryToolFacet(address(diamond)).removeTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        vm.stopPrank();
    }

    /// @notice Test non-owner removal attempt
    function test_removeNonOwner() public {
        vm.startPrank(nonOwner);

        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = TEST_TOOL_CID;

        vm.expectRevert(PKPToolRegistryErrors.NotPKPOwner.selector);
        PKPToolRegistryToolFacet(address(diamond)).removeTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        vm.stopPrank();
    }

    /// @notice Test enabling a single tool
    function test_enableSingleTool() public {
        vm.startPrank(deployer);

        // First register a tool
        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = TEST_TOOL_CID;
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Verify tool is registered and enabled
        bool isEnabled = PKPToolRegistryToolFacet(address(diamond)).isToolRegistered(TEST_PKP_TOKEN_ID, TEST_TOOL_CID);
        assertTrue(isEnabled, "Tool should be enabled after registration");

        // Disable the tool
        PKPToolRegistryToolFacet(address(diamond)).disableTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Verify tool is disabled
        isEnabled = PKPToolRegistryToolFacet(address(diamond)).isToolRegistered(TEST_PKP_TOKEN_ID, TEST_TOOL_CID);
        assertFalse(isEnabled, "Tool should be disabled");

        // Expect the ToolsEnabled event
        vm.expectEmit(true, false, false, true);
        emit ToolsEnabled(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Enable the tool
        PKPToolRegistryToolFacet(address(diamond)).enableTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Verify tool is enabled again
        isEnabled = PKPToolRegistryToolFacet(address(diamond)).isToolRegistered(TEST_PKP_TOKEN_ID, TEST_TOOL_CID);
        assertTrue(isEnabled, "Tool should be enabled after enabling");

        vm.stopPrank();
    }

    /// @notice Test disabling a single tool
    function test_disableSingleTool() public {
        vm.startPrank(deployer);

        // First register a tool
        string[] memory toolIpfsCids = new string[](1);
        toolIpfsCids[0] = TEST_TOOL_CID;
        PKPToolRegistryToolFacet(address(diamond)).registerTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Expect the ToolsDisabled event
        vm.expectEmit(true, false, false, true);
        emit ToolsDisabled(TEST_PKP_TOKEN_ID, toolIpfsCids);

        // Disable the tool
        PKPToolRegistryToolFacet(address(diamond)).disableTools(TEST_PKP_TOKEN_ID, toolIpfsCids);

        vm.stopPrank();
    }

    /// @notice Test getting PKP NFT contract address
    function test_getPKPNFTContract() public {
        address pkpNftContract = PKPToolRegistryToolFacet(address(diamond)).getPKPNFTContract();
        assertEq(pkpNftContract, address(mockPkpNft), "Wrong PKP NFT contract address");
    }
} 