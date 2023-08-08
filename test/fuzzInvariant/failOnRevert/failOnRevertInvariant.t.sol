// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// Invariants:
// 1. protocol must never be insolvent / undercollateralized
// TODO: users cant create stablecoins with a bad health factor
// TODO: a user should only be able to be liquidated if they have a bad health factor


import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";

import {DStableCoin} from "../../../src/DStableCoin.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {FailOnRevertHandler} from "./failOnRevertHandler.t.sol";



contract FailOnRevertInvariants is StdInvariant, Test { 


    DSCEngine public dscEngine;
    DStableCoin public dsc;
    HelperConfig public helperConfig;

    FailOnRevertHandler public handler;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public constant USER = address(1);
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;


    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;


    function setUp() external { 

        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();

        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig(); 

        handler = new FailOnRevertHandler(dsc, dscEngine);
        targetContract(address(handler));                   //targetContract : foundry will target this contract to run the tests      

        // targetContract(address(ethUsdPriceFeed)); Why can't we just do this?
    }


    // invariant keyword indicates invariant test

    // protocol must never be insolvent / undercollateralized
    function invariant_protocolMustHaveMoreValueThatTotalSupplyDollars() public view { 

        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, wethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, wbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersCantRevert() public view {

        dscEngine.getCollateralTokens();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationThreshold();
        dscEngine.getMinHealthFactor();
        dscEngine.getDsc();
        // dsce.getTokenAmountFromUsd();
        // dsce.getCollateralTokenPriceFeed();
        // dsce.getCollateralBalanceOfUser();
        // getAccountCollateralValue();
    }
}