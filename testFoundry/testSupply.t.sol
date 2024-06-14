// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts-5.0/utils/Strings.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/ERC20.sol";
import "../contracts/interface/IPositionRegistry.sol";

import { AaveConnector, BaseConnectorCP } from "contracts/connectors/AaveConnector.sol";
import { IPool } from "contracts/external/interfaces/Aave/IPool.sol";
import "./utils/testStarter.sol";
import "./utils/resources/OptimismAddresses.sol";
import "contracts/accountingManager/NoyaFeeReceiver.sol";
import "forge-std/console.sol";

import { AccessControl } from "@openzeppelin/contracts-5.0/access/AccessControl.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/extensions/ERC20Pausable.sol";

contract SupplyAllPOC is testStarter, OptimismAddresses {
    using SafeERC20 for IERC20;

    AaveConnector connector;

    NoyaFeeReceiver managementFeeReceiver;
    NoyaFeeReceiver performanceFeeReceiver;
    address withdrawFeeReceiver = bob;

    address charlie = makeAddr("charlie");

    mapping(address => string) private addressToUser;

    address public constant USD = address(840);

    function setUp() public {
        // --------------------------------- set env --------------------------------
        uint256 fork = vm.createFork(RPC_URL, startingBlock);
        vm.selectFork(fork);

        console.log("Test timestamp: %s", block.timestamp);

        // --------------------------------- deploy the contracts ---------------------------------
        vm.startPrank(owner);

        deployEverythingNormal(USDC);

        // --------------------------------- init connector ---------------------------------
        connector = new AaveConnector(aavePool, USD, BaseConnectorCP(registry, 0, swapHandler, noyaOracle));

        console.log("AaveConnector deployed: %s", address(connector));
        // ------------------- add connector to registry -------------------
        addConnectorToRegistry(vaultId, address(connector));
        console.log("AaveConnector added to registry");

        addTrustedTokens(vaultId, address(accountingManager), USDC);
        addTrustedTokens(vaultId, address(accountingManager), DAI);

        // ------------------- add oracles -------------------
        addTokenToChainlinkOracle(address(USDC), USD, address(USDC_USD_FEED));
        addTokenToNoyaOracle(address(USDC), address(chainlinkOracle));

        addTokenToChainlinkOracle(address(DAI), USD, address(DAI_USD_FEED));
        addTokenToNoyaOracle(address(DAI), address(chainlinkOracle));

        addRoutesToNoyaOracle(address(DAI), address(USDC), USD);
        console.log("Tokens added to registry");

        registry.addTrustedPosition(vaultId, connector.AAVE_POSITION_ID(), address(connector), true, false, "", "");

        registry.addTrustedPosition(vaultId, 0, address(accountingManager), false, false, abi.encode(USDC), "");
        registry.addTrustedPosition(vaultId, 0, address(accountingManager), false, false, abi.encode(DAI), "");
        console.log("Positions added to registry");

        managementFeeReceiver = new NoyaFeeReceiver(address(accountingManager), baseToken, owner);
        performanceFeeReceiver = new NoyaFeeReceiver(address(accountingManager), baseToken, owner);

        accountingManager.updateValueOracle(noyaOracle);
        vm.stopPrank();

        addressToUser[alice] = "alice";
        addressToUser[bob] = "bob";
        addressToUser[charlie] = "charlie";
    }

    function testSupplyAll() public {
        console.log("=========================================");

        uint256 _amount = 100 * 10 ** ERC20(USDC).decimals();

        giveBaseToken(address(alice), _amount * 10);
        giveBaseToken(address(bob), _amount);
        giveBaseToken(address(charlie), _amount * 10);

        depositToAccountingManager(alice, _amount * 10);

        vm.startPrank(owner);
        accountingManager.calculateDepositShares(10);
        skip(accountingManager.depositWaitingTime());

        accountingManager.executeDeposit(10, address(connector), "");

        console.log("TVL: ", accountingManager.TVL()); // 10 * _amount

        connector.supply(USDC, _amount * 5);

        console.log("TVL: ", accountingManager.TVL()); // 10 * _amount

        connector.supply(USDC, _amount * 5);

        console.log("TVL: ", accountingManager.TVL()); // 0, but should be 10 * _amount

        vm.stopPrank();

        depositToAccountingManager(bob, _amount);

        vm.startPrank(owner);
        accountingManager.calculateDepositShares(10);
        skip(accountingManager.depositWaitingTime());

        accountingManager.executeDeposit(10, address(connector), "");
        vm.stopPrank();

        console.log("TVL: ", accountingManager.TVL()); // 2 * amount, should be 11 * amount

        depositToAccountingManager(charlie, _amount * 5);

        vm.startPrank(owner);
        accountingManager.calculateDepositShares(10);
        skip(accountingManager.depositWaitingTime());
        accountingManager.executeDeposit(10, address(connector), "");
        vm.stopPrank();

        console.log("TVL: ", accountingManager.TVL()); // 12 * amount, should be 16 * amount
    }

    function depositToAccountingManager(address user, uint256 amount) private {
        vm.startPrank(user);
        SafeERC20.forceApprove(IERC20(USDC), address(accountingManager), amount);
        accountingManager.deposit(address(user), amount, address(0));
        vm.stopPrank();
    }

    function giveBaseToken(address to, uint256 amount) private {
        _dealWhale(baseToken, to, address(0x1AB4973a48dc892Cd9971ECE8e01DcC7688f8F23), amount);
    }
}
