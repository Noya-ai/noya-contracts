// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "../../../interface/valueOracle/INoyaValueOracle.sol";
import "../../../interface/valueOracle/AggregatorV3Interface.sol";
import "../../../accountingManager/Registry.sol";
import "@openzeppelin/contracts-5.0/access/Ownable.sol";
import "@openzeppelin/contracts-5.0/token/ERC20/extensions/IERC20Metadata.sol";

contract ChainlinkOracleConnector is INoyaValueOracle {
    PositionRegistry public registry;

    /// @notice The threshold for the age of the price data
    uint256 public defaultChainlinkPriceAgeThreshold = 2 hours;
    mapping(address => uint256) public chainlinkPriceAgeThreshold;

    /*
    * @notice The address of the source of each pair of assets
    * @dev the tokens should be in the same order as in the chainlink contract
    */
    mapping(address => mapping(address => address)) private assetsSources;
    AggregatorV3Interface internal sequencerUptimeFeed;
    uint256 public gracePeriod;

    /*
    * @notice The addresses that represents ETH and USD
    */
    address public constant ETH = address(0);
    address public constant USD = address(840);

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event AssetSourceUpdated(address indexed asset, address indexed baseToken, address indexed source);
    event ChainlinkPriceAgeThresholdUpdated(uint256 newThreshold);
    event ChainlinkPriceAgeThresholdUpdatedForAsset(address source, uint256 newThreshold);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error NoyaChainlinkOracle_DATA_OUT_OF_DATE();
    error NoyaChainlinkOracle_PRICE_ORACLE_UNAVAILABLE(address asset, address baseToken, address source);
    error NoyaChainlinkOracle_INVALID_INPUT();
    error GracePeriodNotOver();
    error SequencerDown();

    modifier onlyMaintainer() {
        if (!registry.hasRole(registry.MAINTAINER_ROLE(), msg.sender)) revert INoyaValueOracle_Unauthorized(msg.sender);
        _;
    }

    constructor(address _reg, address _sequencerUptimeFeed, uint256 _gracePeriod) {
        require(_reg != address(0));
        registry = PositionRegistry(_reg);
        sequencerUptimeFeed = AggregatorV3Interface(_sequencerUptimeFeed);
        gracePeriod = _gracePeriod;
    }

    /*
    * @notice Updates the threshold for the age of the price data
    * @param _chainlinkPriceAgeThreshold The new threshold
    * @dev The threshold should be between 1 day and 10 days
    */
    function updateDefaultChainlinkPriceAgeThreshold(uint256 _chainlinkPriceAgeThreshold) external onlyMaintainer {
        if (_chainlinkPriceAgeThreshold <= 1 hours || _chainlinkPriceAgeThreshold >= 10 days) {
            revert NoyaChainlinkOracle_INVALID_INPUT();
        }
        defaultChainlinkPriceAgeThreshold = _chainlinkPriceAgeThreshold;
        emit ChainlinkPriceAgeThresholdUpdated(_chainlinkPriceAgeThreshold);
    }

    function updateChainlinkPriceAgeThreshold(address source, uint256 _chainlinkPriceAgeThreshold)
        external
        onlyMaintainer
    {
        if (_chainlinkPriceAgeThreshold <= 1 hours || _chainlinkPriceAgeThreshold >= 10 days) {
            revert NoyaChainlinkOracle_INVALID_INPUT();
        }
        chainlinkPriceAgeThreshold[source] = _chainlinkPriceAgeThreshold;
        emit ChainlinkPriceAgeThresholdUpdatedForAsset(source, _chainlinkPriceAgeThreshold);
    }

    /*
    * @notice Updates the source of an asset
    * @param assets The addresses of the assets
    * @param baseTokens The addresses of the base tokens
    * @param sources The address of the source of each asset
    */
    function setAssetSources(address[] calldata assets, address[] calldata baseTokens, address[] calldata sources)
        external
        onlyMaintainer
    {
        for (uint256 i = 0; i < assets.length; i++) {
            assetsSources[assets[i]][baseTokens[i]] = sources[i];
            emit AssetSourceUpdated(assets[i], baseTokens[i], sources[i]);
        }
    }

    /*
    * @notice Gets the value of an asset in terms of a base Token
    * @param asset The address of the asset
    * @param baseToken The address of the base Token
    * @param amount The amount of the asset
    * @return The value of the asset in terms of the base Token
    * @dev The value is returned in the asset token decimals
    * @dev If the tokens are not ETH or USD, it should support the decimals() function in IERC20Metadata interface since the logic depends on it
    */
    function getValue(address asset, address baseToken, uint256 amount) public view returns (uint256) {
        if (asset == baseToken) {
            return amount;
        }

        (address primarySource, bool isPrimaryInverse) = getSourceOfAsset(asset, baseToken);
        if (primarySource == address(0)) {
            revert NoyaChainlinkOracle_PRICE_ORACLE_UNAVAILABLE(asset, baseToken, primarySource);
        }
        address decimalsSource = isPrimaryInverse ? baseToken : asset;
        decimalsSource = decimalsSource == ETH || decimalsSource == USD ? primarySource : decimalsSource;
        return getValueFromChainlinkFeed(
            AggregatorV3Interface(primarySource), amount, getTokenDecimals(decimalsSource), isPrimaryInverse
        );
    }

    /*
    * @notice Gets the chainlink price feed contract and returns the value of an asset in terms of a base Token
    * @param source The address of the chainlink price feed contract
    * @param amountIn The amount of the asset
    * @param sourceTokenUnit The unit of the asset
    * @param isInverse Whether the price feed is inverse or not
    * @return The value of the asset in terms of the base Token
    * @dev The chainlink price feed data should be up to date
    * @dev The Chainlink price is the price of a token based on another token(or currency) so if we need to claculate the price of the later based on the first, we should put isInverse to true
    */
    function getValueFromChainlinkFeed(
        AggregatorV3Interface source,
        uint256 amountIn,
        uint256 sourceTokenUnit,
        bool isInverse
    ) public view returns (uint256) {
        if (address(sequencerUptimeFeed) != address(0)) {
            (, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();
            bool isSequencerUp = answer == 0;
            if (!isSequencerUp) {
                revert SequencerDown();
            }
            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= gracePeriod) {
                revert GracePeriodNotOver();
            }
        }
        uint256 uintprice = getPrice(address(source));
        if (isInverse) {
            return (amountIn * sourceTokenUnit) / uintprice;
        }
        return (amountIn * uintprice) / (sourceTokenUnit);
    }

    function getPrice(address source) public view returns (uint256) {
        int256 price;
        uint256 updatedAt;
        (, price,, updatedAt,) = AggregatorV3Interface(source).latestRoundData();
        uint256 uintprice = uint256(price);
        uint256 ageThreshold = chainlinkPriceAgeThreshold[source];
        if (ageThreshold == 0) {
            ageThreshold = defaultChainlinkPriceAgeThreshold;
        }
        if (block.timestamp - updatedAt > ageThreshold) {
            revert NoyaChainlinkOracle_DATA_OUT_OF_DATE();
        }
        if (price <= 0) {
            revert NoyaChainlinkOracle_PRICE_ORACLE_UNAVAILABLE(address(source), address(0), address(0));
        }
        return uintprice;
    }

    /// @notice Gets the decimals of a token
    function getTokenDecimals(address token) public view returns (uint256) {
        uint256 decimals = IERC20Metadata(token).decimals();
        return 10 ** decimals;
    }

    function getSourceOfAsset(address asset, address baseToken) public view returns (address source, bool isInverse) {
        if (assetsSources[asset][baseToken] != address(0)) {
            return (assetsSources[asset][baseToken], false);
        } else if (assetsSources[baseToken][asset] != address(0)) {
            return (assetsSources[baseToken][asset], true);
        }
        return (address(0), false);
    }
}
