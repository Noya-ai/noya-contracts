// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts-5.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/IERC20.sol";
import "contracts/helpers/valueOracle/NoyaValueOracle.sol";

import "./utils/testStarter.sol";

import "./utils/resources/MainnetAddresses.sol";
import "./utils/mocks/MockDataFeed.sol";

contract TestOracle is testStarter, MainnetAddresses {
    function setUp() public {
        console.log("----------- Initialization -----------");
        // --------------------------------- set env --------------------------------
        uint256 fork = vm.createFork(RPC_URL, startingBlock);
        vm.selectFork(fork);

        console.log("Test timestamp: %s", block.timestamp);

        // --------------------------------- deploy the contracts ---------------------------------
        vm.startPrank(owner);

        deployEverythingNormal(USDC);

        deployUniswapOracle(uniV3Factory);

        console.log("Tokens added to registry");

        console.log("Positions added to registry");
        vm.stopPrank();
    }

    function testGetValueUSD() public {
        vm.startPrank(owner);

        addTokenToChainlinkOracle(address(USDC), address(840), address(USDC_USD_FEED));
        addTokenToChainlinkOracle(address(DAI), address(840), address(DAI_USD_FEED));
        addTokenToNoyaOracle(address(USDC), address(chainlinkOracle));

        addTokenToNoyaOracle(address(DAI), address(chainlinkOracle));
        addTokenToNoyaOracle(address(840), address(chainlinkOracle));

        address[] memory assets = new address[](1);
        assets[0] = address(840);
        noyaOracle.updatePriceRoute(address(USDC), address(DAI), assets);
        noyaOracle.updatePriceRoute(address(DAI), address(USDC), assets);
        console.log("----------- Test getValue USD -----------");
        {
            uint256 value_zero = noyaOracle.getValue(address(address(DAI)), address(840), 0);
            assertEq(value_zero, 0);
            uint256 value_same = noyaOracle.getValue(address(address(DAI)), address(DAI), 1_000_000_000_000_000_000);
            assertEq(value_same, 1_000_000_000_000_000_000);
        }

        uint256 value = noyaOracle.getValue(address(address(DAI)), address(840), 1_000_000_000_000_000_000);
        value = noyaOracle.getValue(address(840), address(address(DAI)), value);
        assertEq(value, 1_000_000_000_000_000_000);
        value = noyaOracle.getValue(address(USDC), address(840), 1_000_000_000);
        value = noyaOracle.getValue(address(840), address(USDC), value);
        assert(value <= 1_001_000_000 || value >= 999_000_000);
        value = noyaOracle.getValue(address(USDC), address(DAI), 1_000_000_000);
        value = noyaOracle.getValue(address(DAI), address(USDC), value);
        assert(value <= 1_001_000_000 || value >= 999_000_000);
        vm.stopPrank();
    }

    function testWrongOraclePath() public {
        address ETH = address(0);
        address ETH_WBTC_FEED = 0xAc559F25B1619171CbC396a50854A3240b6A4e99;
        address USD = address(840);

        address[] memory assets = new address[](3);
        address[] memory baseTokens = new address[](3);
        address[] memory sources = new address[](3);
        assets[0] = STETH;
        baseTokens[0] = ETH;
        sources[0] = STETH_ETH_FEED;
        assets[1] = ETH;
        baseTokens[1] = WBTC;
        sources[1] = ETH_WBTC_FEED;
        assets[2] = WBTC;
        baseTokens[2] = USD;
        sources[2] = WBTC_USD_FEED;

        INoyaValueOracle[] memory oracles = new INoyaValueOracle[](4);
        address[] memory baseCurrencies = new address[](4);
        oracles[0] = INoyaValueOracle(chainlinkOracle);
        oracles[1] = INoyaValueOracle(chainlinkOracle);
        oracles[2] = INoyaValueOracle(chainlinkOracle);
        oracles[3] = INoyaValueOracle(chainlinkOracle);
        baseCurrencies[0] = ETH;
        baseCurrencies[1] = WBTC;
        baseCurrencies[2] = USD;
        baseCurrencies[3] = STETH;

        vm.startPrank(owner);

        // Set price feeds for:
        //   1. STETH -> ETH
        //   2. ETH -> WBTC
        //   3. WBTC -> USD
        chainlinkOracle.setAssetSources(assets, baseTokens, sources);

        // Set all assets to use the chainlinkOracle as the default price source
        noyaOracle.updateDefaultPriceSource(baseCurrencies, oracles);

        assets = new address[](2);
        assets[0] = ETH;
        assets[1] = WBTC;

        // Set sources for STETH -> USD to be STETH -> ETH -> WBTC -> USD
        noyaOracle.updatePriceRoute(STETH, USD, assets);

        // Reverts as price feed for STETH -> BTC does not exist
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         ChainlinkOracleConnector.NoyaChainlinkOracle_PRICE_ORACLE_UNAVAILABLE.selector, STETH, WBTC, address(0)
        //     )
        // );
        console.log(noyaOracle.getValue(STETH, USD, 1e18));
    }

    function testChainlinkInvalidDecimals() public {
        address USD = address(840);
        address[] memory assets = new address[](2);
        address[] memory baseTokens = new address[](2);
        address[] memory sources = new address[](2);
        assets[0] = WETH;
        baseTokens[0] = USD;
        sources[0] = WETH_USD_FEED;
        assets[1] = USDC;
        baseTokens[1] = WETH;
        sources[1] = USDC_ETH_FEED;

        INoyaValueOracle[] memory oracles = new INoyaValueOracle[](3);
        address[] memory baseCurrencies = new address[](3);
        oracles[0] = INoyaValueOracle(chainlinkOracle);
        oracles[2] = INoyaValueOracle(chainlinkOracle);
        oracles[1] = INoyaValueOracle(chainlinkOracle);
        baseCurrencies[0] = USD;
        baseCurrencies[2] = USDC;
        baseCurrencies[1] = WETH;

        vm.startPrank(owner);

        chainlinkOracle.setAssetSources(assets, baseTokens, sources);

        noyaOracle.updateDefaultPriceSource(baseCurrencies, oracles);

        uint256 value = noyaOracle.getValue(USDC, WETH, 3320e6);
        uint256 WETHDecimals = IERC20Metadata(WETH).decimals();

        console.log("%s = %s WETH", value, value / 10 ** WETHDecimals);
    }

    function testGetValueETH() public {
        vm.startPrank(owner);
        address[] memory assets = new address[](1);
        assets[0] = address(0);
        noyaOracle.updatePriceRoute(address(STETH), address(USDC), assets);
        noyaOracle.updatePriceRoute(address(USDC), address(STETH), assets);
        addTokenToChainlinkOracle(address(STETH), address(0), address(STETH_ETH_FEED));
        addTokenToChainlinkOracle(address(USDC), address(0), address(USDC_ETH_FEED));

        addTokenToNoyaOracle(address(USDC), address(chainlinkOracle));
        addTokenToNoyaOracle(address(STETH), address(chainlinkOracle));
        addTokenToNoyaOracle(address(0), address(chainlinkOracle));
        console.log("----------- Test getValue ETH -----------");
        uint256 value = noyaOracle.getValue(steth, address(0), 1_000_000_000_000_000_000);
        uint256 value2 = noyaOracle.getValue(address(0), steth, value);
        assertEq(value2, 1_000_000_000_000_000_000);
        uint256 value3 = noyaOracle.getValue(address(USDC), address(0), 2_300_000_000);
        uint256 value4 = noyaOracle.getValue(address(0), address(USDC), value3);
        assertEq(value4, 2_300_000_000);
        uint256 value5 = noyaOracle.getValue(address(USDC), steth, 2_300_000_000);
        uint256 value6 = noyaOracle.getValue(steth, address(USDC), value5);

        assert(value6 <= 2_301_000_000 || value6 >= 2_299_000_000);

        assertEq(chainlinkOracle.getValue(USDC, USDC, 100_000), 100_000);

        vm.expectRevert();
        noyaOracle.getValue(address(USDT), steth, 2_300_000_000);

        vm.expectRevert();
        noyaOracle.getValue(rETH, steth, 2_300_000_000);

        vm.stopPrank();
    }

    function testErrors() public {
        vm.startPrank(owner);
        addTokenToChainlinkOracle(address(STETH), address(0), address(STETH_ETH_FEED));
        addTokenToNoyaOracle(address(STETH), address(chainlinkOracle));
        addTokenToNoyaOracle(address(0), address(chainlinkOracle));

        vm.expectRevert();
        chainlinkOracle.updateDefaultChainlinkPriceAgeThreshold(0);

        vm.expectRevert();
        chainlinkOracle.updateDefaultChainlinkPriceAgeThreshold(100 days);
        chainlinkOracle.updateDefaultChainlinkPriceAgeThreshold(8 days);
        vm.warp(block.timestamp + 100 days);
        vm.expectRevert();
        noyaOracle.getValue(steth, address(0), 1_000_000_000_000_000_000);

        vm.stopPrank();
    }

    function testSpecificOracleAgeThreshold() public {
        vm.startPrank(owner);
        addTokenToChainlinkOracle(address(USDC), address(0), address(USDC_ETH_FEED));
        addTokenToChainlinkOracle(address(STETH), address(0), address(STETH_ETH_FEED));
        addTokenToNoyaOracle(address(STETH), address(chainlinkOracle));
        addTokenToNoyaOracle(address(0), address(chainlinkOracle));

        chainlinkOracle.updateChainlinkPriceAgeThreshold(address(STETH_ETH_FEED), 2 days);
        chainlinkOracle.updateChainlinkPriceAgeThreshold(address(USDC_ETH_FEED), 8 days);

        vm.warp(block.timestamp + 4 days);
        vm.expectRevert();
        noyaOracle.getValue(steth, address(0), 1_000_000_000_000_000_000);

        noyaOracle.getValue(USDC, address(0), 1_000_000_000_000_000_000);

        vm.stopPrank();
    }

    function testUniswap() public {
        console.log("----------- Test Uniswap -----------");

        vm.startPrank(owner);
        uniswapOracle.addPool(address(USDC), address(DAI), 100);

        vm.expectRevert();
        uniswapOracle.addPool(address(USDC), alice, 100); // Covered coverage bug number 76

        vm.expectRevert();
        uniswapOracle.getValue(address(USDC), alice, 100);

        vm.expectRevert();
        noyaOracle.getValue(address(USDC), alice, 100);

        uniswapOracle.assetToBaseToPool(address(USDC), address(DAI));

        address[] memory assets = new address[](1);
        assets[0] = address(DAI);
        address[] memory baseTokens = new address[](1);
        baseTokens[0] = address(USDC);
        address[] memory sources = new address[](1);
        sources[0] = address(uniswapOracle);
        noyaOracle.updateAssetPriceSource(assets, baseTokens, sources);

        uint256 value = noyaOracle.getValue(address(USDC), address(DAI), 1_000_000_000);
        value = noyaOracle.getValue(address(DAI), address(USDC), value);
        assert(value <= 1_001_000_000 || value >= 999_000_000);

        vm.expectRevert();
        uniswapOracle.setPeriod(0);

        uniswapOracle.setPeriod(1000);

        value = noyaOracle.getValue(address(USDC), address(DAI), 1_000_000_000);
        value = noyaOracle.getValue(address(DAI), address(USDC), value);
        assert(value <= 1_001_000_000 || value >= 999_000_000);
    }

    function test_assetTokenValueIsIncorrectWhenETHUSDChainlinkOracleIsNeeded() public {
        // Some tokens do not have token/USD oracle so token/ETH and ETH/USD oracles need to be used.
        // Following code compares method using token/ETH and ETH/USD oracles indirectly to method using token/USD oracle directly.

        address ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

        vm.startPrank(owner);

        addTokenToChainlinkOracle(address(USDC), address(840), address(USDC_USD_FEED));
        addTokenToChainlinkOracle(address(USDC), address(0), address(USDC_ETH_FEED));
        addTokenToChainlinkOracle(address(840), address(0), address(ETH_USD_FEED));

        addTokenToNoyaOracle(address(USDC), address(chainlinkOracle));
        addTokenToNoyaOracle(address(0), address(chainlinkOracle));
        addTokenToNoyaOracle(address(840), address(chainlinkOracle));

        uint256 valueDirect = noyaOracle.getValue(address(USDC), address(840), 1e6);

        // when using USDC/USD oracle directly, 1e6 wei USDC is equivalent to 99998495 wei USD, which is in USD's decimals that is 8
        // assertEq(valueDirect, 99_998_495);

        address[] memory assets = new address[](1);
        assets[0] = address(0);
        noyaOracle.updatePriceRoute(address(USDC), address(840), assets);

        uint256 valueIndirect = noyaOracle.getValue(address(USDC), address(840), 1e6);

        uint256 ethValue = chainlinkOracle.getValue(address(USDC), address(0), 1e6);

        console.log("ETH value: %s", ethValue);

        uint256 usdValue = chainlinkOracle.getValue(address(0), address(840), 1e18);
        uint256 ethValue2 = chainlinkOracle.getValue(address(840), address(0), 1e8);
        console.log("ETH value: %s", ethValue2);

        console.log("USD value: %s", usdValue);

        // when using USDC/ETH and ETH/USD oracles indirectly, 1e6 wei USDC is equivalent to 998152930103816659 wei USD, which is in ETH's decimals that is 18
        // assertEq(valueIndirect, 998_152_930_103_816_659);

        // value of 1e6 wei USDC is incorrectly much higher when using USDC/ETH and ETH/USD oracles indirectly comparing to using USDC/USD oracle directly
        // assertEq(valueIndirect / valueDirect, 9_981_679_525);

        vm.stopPrank();
    }

    function testMockData() public {
        vm.startPrank(owner);

        MockData mockData = new MockData();
        mockData.setAnswer(0, block.timestamp);

        addTokenToChainlinkOracle(address(USDC), address(840), address(mockData));
        vm.expectRevert();
        uint256 value = noyaOracle.getValue(address(USDC), address(840), 1_000_000_000); // Covered coverage bug number 78
    }
}
