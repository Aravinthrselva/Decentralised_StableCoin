//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {DStableCoin} from "../../../src/DStableCoin.sol";
import {DSCEngine, AggregatorV3Interface} from "../../../src/DSCEngine.sol";

import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract FailOnRevertHandler is Test {

    using EnumerableSet for EnumerableSet.AddressSet;

    // Deployed contracts to interact with
    DStableCoin public dsc;
    DSCEngine public dscEngine;
 
    MockV3Aggregator public ethUsdPriceContract;
    MockV3Aggregator public btcUsdPriceContract;

    ERC20Mock public wethContract;
    ERC20Mock public wbtcContract;

    // Ghost Variables
    // max cant be uint256 max -- since adding + 1 to the max uint256 value will revert the runs during fuzzing
    uint96 public constant MAX_UINT96 = type(uint96).max;



    constructor(DStableCoin _dsc, DSCEngine _dscEngine) { 

        dsc = _dsc;
        dscEngine = _dscEngine;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        wethContract = ERC20Mock(collateralTokens[0]);
        wbtcContract = ERC20Mock(collateralTokens[1]);

        ethUsdPriceContract = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wethContract)));
        btcUsdPriceContract = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtcContract)));
    }


/* FUNCTOINS TO INTERACT WITH */

    ///////////////
    // DSCEngine //
    ///////////////


    function mintAndDepositCollateral(uint256 collateralSeed, uint256 amountCollateral) public { 

        
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // must be more than 0 , since we know  amountCollateral= 0 will revert the tx 
        amountCollateral = bound(amountCollateral, 1, MAX_UINT96);  // MAX_UINT96 = type(uint96).max;
        
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

    }


    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public { 

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));


        // we cant set min value to 1 here, since if maxcollateral above returns 0 --
        // then we have a situation where min = 1 & max = 0 -- which is an issue
        // so we adapt a different design pattern & return IF amountCollateral is 0 
        amountCollateral = bound(amountCollateral, 0, maxCollateral);
        if (amountCollateral == 0) {
            return;
            //vm.assume(bool) // can vm.assume be used here instead to re-run the test with diff inputs?
        }

        dscEngine.redeemCollateral(address(collateral), amountCollateral);

    }


    /*  DSCEngine can mint DSC! */

    // function mintDsc(uint256 amountDsc) public {
    //     amountDsc = bound(amountDsc, 1, MAX_DEPOSIT_SIZE);
    //     vm.prank(dsc.owner());
    //     dsc.mint(msg.sender, amountDsc);
    // }

    function burnDsc(uint256 amountDsc) public { 

        // Must burn more than 0
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));
        if(amountDsc == 0) {
            return;
        }

        dscEngine.burnDsc(amountDsc);

    }



    function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public { 

        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        uint256 userHealthFactor = dscEngine.getHealthFactor(userToBeLiquidated);
        if(userHealthFactor >= minHealthFactor) {
             return;
        }
        
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        debtToCover = bound(debtToCover, 1, uint256(MAX_UINT96));                   // MAX_UINT96 = type(uint96).max;

        dscEngine.liquidate(address(collateral), userToBeLiquidated, debtToCover);

    }

    ////////////////////
    // DStableCoin    //
    ////////////////////

    function transferDsc(uint256 amountDsc, address to) public { 

         if (to == address(0)) {
            to = address(1);
         }   

         amountDsc = bound(amountDsc, 0, dsc.balanceOf(msg.sender));    
        
        vm.prank(msg.sender);
        dsc.transfer(to, amountDsc);
    }


    ////////////////
    // Aggregator //
    ////////////////

    function updateCollateralPrice(uint256 collateralSeed, uint96 newPrice) public { 

        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        int256 intNewPrice = int256(uint256(newPrice));

        MockV3Aggregator priceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(collateral)));

        priceFeed.updateAnswer(intNewPrice);
    }



/* Helper Functions*/

    function _getCollateralFromSeed(uint256 _randomSeed) private view returns(ERC20Mock) {

        if(_randomSeed % 2 == 0) {

            return wethContract;
        } else {

        return wbtcContract;
        }
    }
}