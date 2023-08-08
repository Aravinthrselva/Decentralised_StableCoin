// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {DStableCoin} from "../../src/DStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";

import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";

contract DSCEngineTest is StdCheats, Test {
    
    DStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;


    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address public user = address(1);
    uint256 public constant STARTING_USER_BALANCE = 100 ether;

    uint256 constant AMOUNT_COLLATERAL = 10 ether;
    uint256 constant AMOUNT_DSC_MINT = 100 ether;

    // liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;


    function setUp() external {

        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        if(block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }

        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);

    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public { 

        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine_tokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

    }

    //////////////////
    // Price Tests  //
    //////////////////

    // This works Only of LOCAL Blockchain with mock contracts
    // Live contracts have varying prices

    function testGetUsdValue() public view {
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsdValue = 28000e18;

        uint256 usdValueReturned = dscEngine.getUsdValue(weth, 14 ether);

        assert(expectedUsdValue == usdValueReturned);
    
    }

    function testGetTokenAmountFromUsd() public {
       //  $2000 = 1 ETH
       //  $500  = 0.25 Eth
        uint256 usdAmount = 500 ether;   // equals $500 ||| ether - 18 decimals
        uint expectedTokenAmount = 0.25 ether;
        uint256 returnedTokenAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedTokenAmount, returnedTokenAmount);

    }


    //////////////////////////////////
    // depositCollateral Tests      //
    //////////////////////////////////

    // testRevertsIfTransferFromFails : this test is based on the MockFailedTransferFrom setup

    function testRevertsIfTransferFromFails() public { 
        
        // Arrange - setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        
        tokenAddresses = [address(mockDsc)];          // proving the DSC token as approved collateral
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        
        mockDsc.mint(user, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine)); 

        // Arrange - user
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), AMOUNT_COLLATERAL); 

        vm.expectRevert(DSCEngine.DSCEngine_transferFailed.selector);
        mockDscEngine.depositCollateral(address(mockDsc), 1 ether);

        vm.stopPrank();
    }


    function testRevertsIfCollateralZero() public { 

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 4);                   // 4 wei
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);

        vm.stopPrank();

    }


    function testRevertsWithUnapporvedCollateralAddress() public {
        
        vm.startPrank(user);
        ERC20Mock rand = new ERC20Mock("Random Token", "Rand", user, 69e8);
        rand.approve(address(dscEngine), 4);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_tokenNotAllowed.selector, address(rand)));
        dscEngine.depositCollateral(address(rand), 1); 


        vm.stopPrank();

    }

    /** Modifer  */
    modifier depositCollateral() { 

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);                   // AMOUNT_COLLATERAL = 10 ether      
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositCollateral {

        uint256 userBalance = dsc.balanceOf(user);        
        assertEq(userBalance, 0);     
    }


    function testCollateralDepositedInEngine() public depositCollateral { 

        uint256 dscEngineBalance = ERC20Mock(weth).balanceOf(address(dscEngine));
        assertEq(dscEngineBalance, AMOUNT_COLLATERAL);
    }


    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral { 


        (uint256 totalDscMintedByUser , uint256 totalCollateralOfUser) = dscEngine.getAccountInformation(user);

        uint256 expectedTokenAmount = dscEngine.getTokenAmountFromUsd(weth, totalCollateralOfUser);


        assert(totalDscMintedByUser == 0);
        assert(expectedTokenAmount == AMOUNT_COLLATERAL);

    }



    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////    

     // This test depends on the  MockFailedMintDsc setup
    function testRevertsIfMintFails() public { 

        address owner = msg.sender;
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        mockDsc.transferOwnership(address(mockDscEngine));

        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine_MintFailed.selector);
        mockDscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINT); // AMOUNT_DSC_MINT = $100 in DSC - 18 decimals
        
        vm.stopPrank();

    } 

    function testRevertsIfMintedDscBreaksHealthFactor() public {


        uint256 collateralValueInUsd =  dscEngine.getUsdValue(weth, 1 ether);

        // diving by 2 to get to 50% threshold
        // adding 1 unit more than 50% threshold -- so health factor should break
        uint256 amountDscToMintInUsd = (collateralValueInUsd / 2 ) + 1;   
        
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        //lets first calculate the expected health factor when we call the depositCollateralAndMintDsc function
        // calculateHealthFactor takes (mintedDsc, collateralValueInUsd)
        // we have 1 ether in collateral = $ 2000 USD  (as per the V3mock contract)
        // we are only allowed to mint 1000 DSC as per the 50% threshold limit
        // we are attempting to mint 1001 DSC tokens  

        uint256 userHealthFactor = dscEngine.calculateHealthFactor(amountDscToMintInUsd, collateralValueInUsd);  

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BreaksHealthFactor.selector, userHealthFactor));

        // (address tokenCollateralAddr, uint256 amountCollateral, uint256 amountDscToMint)
        dscEngine.depositCollateralAndMintDsc(weth, 1 ether, amountDscToMintInUsd);

        vm.stopPrank();

    }

    /** Modifer  */
    modifier depositedCollateralAndMintedDsc() {  

        vm.startPrank(user);

        // AMOUNT_COLLATERAL = 10 ether  // $20,000 in Eth
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINT);  // AMOUNT_DSC_MINT = $100 in DSC - 18 decimals

        vm.stopPrank();
        _;

    }


    function testRevertsIfMintAmountIsZero() public depositedCollateralAndMintedDsc {

        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {

        vm.startPrank(user);

        dscEngine.mintDsc(501 ether);

        // testing the ERC20 DSC stablecoin contract
        assert(dsc.balanceOf(user) == 601 ether);      // 100 from modifier + 501 = 601

        // testing the dscEngine mapping
        assert(dscEngine.getDscBalanceOfUser(user) == 601 ether);  
  
        vm.stopPrank();

    }


    /////////////////////////
    // burnDsc Tests       //
    /////////////////////////


    function testRevertsIfBurnAmountIsZero() public depositedCollateralAndMintedDsc {

        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
    }



    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        dscEngine.burnDsc(1);
    }


    function testCanBurnDsc() public depositedCollateralAndMintedDsc {

        vm.startPrank(user);
        dsc.approve(address(dscEngine), 100 ether);        // approving the dscEngine contract to take our DSC during burn - $100
        dscEngine.burnDsc(49 ether);                       // burning $49 of DSC 

        assert(dsc.balanceOf(user) == 51 ether);           // $51 of DSC left after burn
        assert(dscEngine.getDscBalanceOfUser(user) == 51 ether);

        vm.stopPrank();
    }



    //////////////////////////////////
    // redeemCollateral Tests      //
    /////////////////////////////////

    // this test depends on the MockFailedTransfer setup

    function testRevertsIfTransferFails() public { 

        //Arrange - setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        mockDsc.mint(user, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine));

        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        mockDscEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine_transferFailed.selector);
        mockDscEngine.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }


    function testRevertsIfRedeemAmountIsZero() public depositedCollateralAndMintedDsc {

        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);

    }


    function testCanRedeemSomeCollateral() public depositedCollateralAndMintedDsc {

        vm.prank(user);
       //depositedCollateralAndMintedDsc modifier deposited 10 ether of collateral

        dscEngine.redeemCollateral(weth, 1 ether);  // withdrawing 1 ether of collateral

        
        uint256 expectedCollateralBalance = 9 ether;  // 10 - 1 
        uint256 ethCollateralBalanceOfUser = dscEngine.getCollateralBalanceOfUser(user, weth);
        
        assertEq(expectedCollateralBalance, ethCollateralBalanceOfUser);
    }


    function testCanRedeemAllCollateral() public depositCollateral {

        vm.startPrank(user);
       //depositCollateral modifier deposited 10 ether of collateral -- but did NOT mint any DSC

        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);  // withdrawing 10 ether of collateral

       
        uint256 expectedCollateralBalance = 0 ether;  // 10 - 10 

        // testing the DSCEngine contract
        uint256 ethCollateralBalanceOfUser = dscEngine.getCollateralBalanceOfUser(user, weth);
        // balance of user maintained by the weth contract
        uint256 userBalanceInWeth = ERC20Mock(weth).balanceOf(user);

        assert(ethCollateralBalanceOfUser == expectedCollateralBalance);

        // confirming with the weth contract
        assert(userBalanceInWeth == STARTING_USER_BALANCE);  // STARTING_USER_BALANCE - 100 ether
      
        vm.stopPrank();
    }    

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testCanRedeemDepositedCollateralAndBurnDsc() public depositedCollateralAndMintedDsc {
        
        // depositedCollateralAndMintedDsc modifier -> deposited 10 eth , minted $100 DSC
        vm.startPrank(user);
        
        dsc.approve(address(dscEngine), 100 ether);       // approving engine contract to burn $100 of our DSC
        uint256 amountCollateralToRedeem = 2 ether;
        uint256 amountDscToBurn = 20 ether;
        // (address collateralTokenAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        dscEngine.redeemCollateralForDsc(weth, amountCollateralToRedeem, amountDscToBurn);

        uint256 ethCollateralBalanceOfUser = dscEngine.getCollateralBalanceOfUser(user, weth);
        uint256 expectedCollateralBalance = 8 ether;  // 10 - 2 

        uint256 dscBalanceOfUser = dsc.balanceOf(user);

        assert(ethCollateralBalanceOfUser == expectedCollateralBalance);
        assert(dscBalanceOfUser == 80 ether);

        vm.stopPrank();

    }


    ////////////////////////
    // healthFactor Tests //
    ////////////////////////


    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {

        // depositedCollateralAndMintedDsc modifier -> deposited 10 eth , minted $100 DSC
        uint256 accountCollateralValueInUsd = dscEngine.getAccountCollateralValue(user);
        uint256 thresholdAdjustedCollateral = accountCollateralValueInUsd / 2 ;

        // 20,000 / 2 = 10,000
        // 10,000 / 100 = 100
        uint256 expectedHealthFactor = (thresholdAdjustedCollateral * 1e18) / 100 ether ;   // expectedHealthFactor = 100 ether

        console.log("(testProperlyReportsHealthFactor) accountCollateralValueInUsd :", accountCollateralValueInUsd / 1e18);
        console.log("(testProperlyReportsHealthFactor) expectedHealthFactor :", expectedHealthFactor / 1e18);

        uint256 returnedHealthFactor = dscEngine.getHealthFactor(user);

        assert(returnedHealthFactor == expectedHealthFactor);

    }


    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc { 

        int256 ethUsdLatestPrice = 18e8;     // 1 ETH = $18 (Eth price crashsed to $18)

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdLatestPrice);

        uint256 userHealthFactor = dscEngine.getHealthFactor(user);

        // collateral   : 10 ether * 18 usd/eth  = $180 
        // mintedDSC    : $100
        // HealthFactor : (180/2) / 100 = 90/100 = 0.9 
        assert(userHealthFactor == 0.9 ether);
        assert(userHealthFactor < 1e18);
        
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test depends on the MockMoreDebtDSC setup

    function testRevertsIfHealthFactorNotImprovedOnLiquidation() public {  

        // Arrange - Setup
        address owner = msg.sender;
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        
        mockDsc.transferOwnership(address(mockDscEngine));

        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        mockDscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINT); // AMOUNT_DSC_MINT = $100 DSC
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;                                // collateralToCover = initially decalred 20 ether
        ERC20Mock(weth).mint(liquidator, collateralToCover);        

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDscEngine), collateralToCover);
        uint256 debtToCover = 10 ether;                             // $10 DSC
        mockDscEngine.depositCollateralAndMintDsc(weth, collateralToCover, AMOUNT_DSC_MINT);
        mockDsc.approve(address(mockDscEngine), debtToCover);

        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);


        vm.expectRevert(DSCEngine.DSCEngine_HealthFactorNotImproved.selector);
        mockDscEngine.liquidate(weth, user, debtToCover);        //  debtToCover --  $10 DSC
        
        vm.stopPrank();
    }



    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {

        console.log("liquidator: ", liquidator);
        ERC20Mock(weth).mint(liquidator, collateralToCover);
        
        vm.startPrank(liquidator);
        
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(weth, collateralToCover, AMOUNT_DSC_MINT);    // AMOUNT_DSC_MINT = 100 ether
        
        dsc.approve(address(dscEngine), AMOUNT_DSC_MINT);

        vm.expectRevert(DSCEngine.DSCEngine_HealthFactorOk.selector);

        //liquidate(address collateralTokenAddress, address victim, uint256 debtToCover)
        dscEngine.liquidate(weth, user, AMOUNT_DSC_MINT);  // AMOUNT_DSC_MINT = 100 ether

        vm.stopPrank();

    }    

    modifier liquidated() { 

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINT);  // weth, 10 , 100
        vm.stopPrank();

        int256 ethUsdLatestPrice = 18e8;                   // $18 with 8 decimals
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdLatestPrice);


        ERC20Mock(weth).mint(liquidator, collateralToCover);   // collateralToCover = 20 ether
        
        vm.startPrank(liquidator);
        
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(weth, collateralToCover, AMOUNT_DSC_MINT );

        dsc.approve(address(dscEngine), AMOUNT_DSC_MINT);

        dscEngine.liquidate(weth, user, AMOUNT_DSC_MINT);  // We are covering their whole debt 

        vm.stopPrank();

        _;

    }


    function testLiquidationPayoutIsCorrect() public liquidated { 

        uint256 liquidatorCollateralBalance = ERC20Mock(weth).balanceOf(liquidator);

        uint256 tokenAmountFromDebtCovered = dscEngine.getTokenAmountFromUsd(weth, AMOUNT_DSC_MINT); // AMOUNT_DSC_MINT-100 => 5.555555556
        uint256 tenPercentCollateralBonus = (tokenAmountFromDebtCovered * 10) / 100;   // 0.55555555556        

        uint256 expectedFinalCollateralWithBonus = tokenAmountFromDebtCovered + tenPercentCollateralBonus;

        uint256 hardCodedExpected = 6111111111111111110;  // 5.55555555556 + 0.5555555556 = 6 111 111 111 111 111 110 / 18 decimals

        assertEq(liquidatorCollateralBalance, expectedFinalCollateralWithBonus);
        assert(liquidatorCollateralBalance == hardCodedExpected);

    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated { 

        uint256 userCollateralBalance = dscEngine.getCollateralBalanceOfUser(user, weth);

        uint256 expectedCollateralBalance = 10 ether - 6111111111111111110;   // initial collateral - liquidated

        assert(userCollateralBalance == expectedCollateralBalance);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated { 

        (uint256 liquidatorDscMinted, ) = dscEngine.getAccountInformation(liquidator);

        uint256 dscBalanceOfLiquidator =  dscEngine.getDscBalanceOfUser(liquidator);

        assertEq(liquidatorDscMinted, 100 ether);
        assert(dscBalanceOfLiquidator == 100 ether);
    }

    function testUserHasNoMoreDebt() public liquidated { 

        (uint256 userDscMinted,) = dscEngine.getAccountInformation(user);

        uint256 dscBalanceOfuser =  dscEngine.getDscBalanceOfUser(user);

        assertEq(userDscMinted, 0 ) ;
        assert(dscBalanceOfuser == 0 );
    }

    ///////////////////////////////////
    // View & Pure Function Tests    //
    //////////////////////////////////

    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = dscEngine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }   
    
    function testGetDsc() public {
        address dscAddress = dscEngine.getDsc();
        assertEq(dscAddress, address(dsc));
    }     
}