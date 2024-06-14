// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "./utils/testStarter.sol";
import "contracts/helpers/BaseConnector.sol";
import "contracts/accountingManager/NoyaFeeReceiver.sol";
import "./utils/resources/OptimismAddresses.sol";
import "contracts/governance/Keepers.sol";

contract TestWithdrawError is testStarter, OptimismAddresses {
    using SafeERC20 for IERC20;

    address connector;
    NoyaFeeReceiver managementFeeReceiver;
    NoyaFeeReceiver performanceFeeReceiver;
    address withdrawFeeReceiver = bob;

    uint256 privateKey1 = 0x99ba14aff4aba765903a41b48aacdf600b6fcdb2b0c2424cd2f8f2c089f20476;
    uint256 privateKey2 = 0x68ab62e784b873b929e98fc6b6696abcc624cf71af05bf8d88b4287e9b58ab99;
    uint256 privateKey3 = 0x952b55e8680117e6de5bde1d3e7902baa89bfde931538a5bb42ba392ef3464a4;
    uint256 privateKey4 = 0x885f1d08ebc23709517fedbec64418e4a09ac1e47e976c868fd8c93de0f88f09;

    WithdrawErrorHandler withdrawErrorsHandler;

    function setUp() public {
        // --------------------------------- set env --------------------------------
        uint256 fork = vm.createFork(RPC_URL, startingBlock);
        vm.selectFork(fork);

        console.log("Test timestamp: %s", block.timestamp);

        // --------------------------------- deploy the contracts ---------------------------------
        vm.startPrank(owner);

        deployEverythingNormal(USDC);

        // --------------------------------- init connector ---------------------------------
        connector = address(new BaseConnector(BaseConnectorCP(registry, 0, swapHandler, noyaOracle)));

        // ------------------- add connector to registry -------------------
        addConnectorToRegistry(vaultId, connector);
        console.log("AaveConnector added to registry");

        addTrustedTokens(vaultId, address(accountingManager), USDC);
        addTrustedTokens(vaultId, address(accountingManager), DAI);

        addTokenToChainlinkOracle(address(USDC), address(840), address(USDC_USD_FEED));
        addTokenToNoyaOracle(address(USDC), address(chainlinkOracle));

        addTokenToChainlinkOracle(address(DAI), address(840), address(DAI_USD_FEED));
        addTokenToNoyaOracle(address(DAI), address(chainlinkOracle));

        console.log("Tokens added to registry");
        registry.addTrustedPosition(vaultId, 0, address(accountingManager), false, false, abi.encode(USDC), "");
        registry.addTrustedPosition(vaultId, 0, address(accountingManager), false, false, abi.encode(DAI), "");
        console.log("Positions added to registry");

        managementFeeReceiver = new NoyaFeeReceiver(address(accountingManager), baseToken, owner);
        performanceFeeReceiver = new NoyaFeeReceiver(address(accountingManager), baseToken, owner);

        accountingManager.updateValueOracle(noyaOracle);
        withdrawErrorsHandler = new WithdrawErrorHandler();
        withdrawErrorsHandler.grantRole(withdrawErrorsHandler.ACCOUNTING_ROLE(), address(accountingManager));
        accountingManager.updateWithdrawErrorsHandler(address(withdrawErrorsHandler));

        vm.stopPrank();
    }

    function testWithdrawError() public {
        uint256 _amount = 10_000 * 1e6;
        console.log("  Balance before deposit: %s USDC", _amount / 1e6);
        _dealWhale(baseToken, address(alice), address(0x1AB4973a48dc892Cd9971ECE8e01DcC7688f8F23), _amount);

        vm.startPrank(alice);

        SafeERC20.forceApprove(IERC20(USDC), address(accountingManager), _amount);

        accountingManager.deposit(address(alice), _amount, address(0));

        vm.stopPrank();
        vm.startPrank(owner);

        accountingManager.calculateDepositShares(10);

        vm.warp(block.timestamp + 35 minutes);

        accountingManager.executeDeposit(10, connector, "");

        vm.stopPrank();
        vm.startPrank(alice);
        uint256 _amount2 = accountingManager.balanceOf(address(alice));
        accountingManager.withdraw(_amount2, address(0));

        vm.stopPrank();
        vm.startPrank(owner);
        accountingManager.calculateWithdrawShares(10);

        accountingManager.startCurrentWithdrawGroup();

        bytes memory data = hex"1232";

        RetrieveData[] memory retrieveData = new RetrieveData[](1);
        retrieveData[0] = RetrieveData(_amount, address(connector), abi.encode(_amount, data));
        accountingManager.retrieveTokensForWithdraw(retrieveData, address(0), "");

        accountingManager.fulfillCurrentWithdrawGroup();

        vm.warp(block.timestamp + 7 hours);

        accountingManager.executeWithdraw(10);

        withdrawErrorsHandler.handleWithdrawalErrors(0, address(alice));
        assertEq(IERC20(USDC).balanceOf(address(alice)), _amount);
    }
}
