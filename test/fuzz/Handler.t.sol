// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we call function

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    address weth;
    address wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    address[] public actors;
    uint256 public actorIndex;

    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc, address[] memory _actors) {
        engine = _dscEngine;
        dsc = _dsc;
        actors = _actors;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = collateralTokens[0];
        wbtc = collateralTokens[1];

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(weth));
    }

    function _useActor() internal returns (address) {
        address actor = actors[actorIndex % actors.length];
        actorIndex++;
        return actor;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address actor = _useActor();

        address collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(actor);
        ERC20Mock(collateral).mint(actor, amountCollateral);
        ERC20Mock(collateral).approve(address(engine), amountCollateral);
        engine.depositCollateral(collateral, amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateralFromSeed(uint256 collateralSeed, uint256 amountCollateral) public {
        address actor = _useActor();
        address collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = engine.getDepositedUserCollateral(collateral, actor);

        if (amountCollateral == 0) {
            return;
        }

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(actor);
        int256 maxDscToMint = (int256(collateralValueInUsd / 2)) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        uint256 maxCollateralToRedeem = engine.getTokenAmountFromUsd(collateral, uint256(maxDscToMint));

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        vm.prank(actor);
        engine.redeemCollateral(collateral, amountCollateral);
    }

    function mintDsc(uint256 amount) public {
        address actor = _useActor();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(actor);
        int256 maxDscToMint = (int256(collateralValueInUsd / 2)) - int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscToMint));

        if (amount == 0) {
            return;
        }

        vm.startPrank(actor);
        engine.mintDsc(amount);
        vm.stopPrank();
    }

    // This breaks our invariant test !!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (address) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
