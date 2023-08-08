// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

pragma solidity 0.8.19;

import {DStableCoin} from "./DStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Aravinth Selva
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with following properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. 
 * It handles all the logic for minting and redeeming DSC, 
 * as well as depositing and withdrawing collateral.
 * 
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // Errors        //
    ///////////////////

    error DSCEngine_tokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_NeedsMoreThanZero();
    error DSCEngine_tokenNotAllowed(address token);
    error DSCEngine_transferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine_MintFailed();
    error DSCEngine_HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();

    //////////////////////////
    // State Variables     // 
    /////////////////////////

    DStableCoin private immutable i_dsc;


    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant PRECISION_18_DECIMALS = 1e18;
    uint256 private constant PRECISION_10_DECIMALS = 1e10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating

    mapping (address => address) private s_priceFeeds;
    mapping (address => mapping (address =>uint256)) private s_trackCollateralDeposited;
    mapping (address => uint256) private s_DscMinted;


    address[] private s_collateralTokens;

    ///////////////////
    // Events        //
    ///////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, uint256 indexed amountCollateral, address from, address to); 
    // if from != to, then it was liquidated



    ///////////////////
    // modifiers     //
    ///////////////////

    modifier nonZeroAmount(uint256 _amount) {

        if(_amount <= 0) {
            revert DSCEngine_NeedsMoreThanZero();
        }

        _;
    }

    modifier isTokenAllowed (address _tokenAddress) {

        if(s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine_tokenNotAllowed(_tokenAddress);
        }

        _;
    }



    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress ) {
    
        if(tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_tokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for(uint256 i=0; i<tokenAddresses.length; i++) {

            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DStableCoin(dscAddress);

    }

    ///////////////////
    // External Functions
    ///////////////////

    function depositCollateralAndMintDsc(address tokenCollateralAddr, uint256 amountCollateral, uint256 amountDscToMint) external {

        depositCollateral(tokenCollateralAddr, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */

    function redeemCollateralForDsc(address collateralTokenAddress, uint256 amountCollateral, uint256 amountDscToBurn) external 
                                nonZeroAmount(amountCollateral) {

        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(collateralTokenAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);                  
    }

    /*
        In order to redeem collateral -- health factor must be above 1 AFTER collateral is withdrawn  
       
     */
    function redeemCollateral(address collateralTokenAddress, uint256 amountToRedeem) external nonZeroAmount(amountToRedeem) nonReentrant {
        
        _redeemCollateral(collateralTokenAddress, amountToRedeem, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }


     /*
     * @notice careful! You'll burn your own DSC here! 
     * @dev use this if you're unsure you might get liquidated 
     * and want to just burn your DSC 
     * but keep your collateral in.
     */

    function burnDsc(uint256 amountToBurn) external nonZeroAmount(amountToBurn) {

        _burnDsc(amountToBurn, msg.sender, msg.sender);

        // Hypothetically NOT needed -- burning DSC is only going to improve health factor
        _revertIfHealthFactorIsBroken(msg.sender); 
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */


    function liquidate(address collateralTokenAddress, address victim, uint256 debtToCover) external nonZeroAmount(debtToCover) nonReentrant {

        uint256 startingVictimHealthFactor = _healthFactor(victim);

        if(startingVictimHealthFactor >= MIN_HEALTH_FACTOR) {
                revert DSCEngine_HealthFactorOk();
        }

        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralTokenAddress, debtToCover);

        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100 ;

        uint256 totalCollateralAfterBonus = tokenAmountFromDebtCovered + bonusCollateral;

        _burnDsc(debtToCover, victim, msg.sender);

        _redeemCollateral(collateralTokenAddress, totalCollateralAfterBonus, victim, msg.sender);

        uint256 endingVictimHealthFactor = _healthFactor(victim);

        if(endingVictimHealthFactor <= startingVictimHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    
    /* Public Functions  */
    
    function depositCollateral(address tokenCollateralAddr, uint256 amountCollateral)  public
             nonZeroAmount(amountCollateral) 
             isTokenAllowed(tokenCollateralAddr) 
             nonReentrant {

            s_trackCollateralDeposited[msg.sender][tokenCollateralAddr] += amountCollateral;

            emit CollateralDeposited(msg.sender, tokenCollateralAddr, amountCollateral);

            bool success = IERC20(tokenCollateralAddr).transferFrom(msg.sender, address(this), amountCollateral);

            if(!success) {
                revert DSCEngine_transferFailed(); 
            }
    }

   
    function mintDsc(uint256 amountDscToMint) public nonZeroAmount(amountDscToMint)  {

        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool isMinted = i_dsc.mint(msg.sender, amountDscToMint);

        if(isMinted != true) {
            revert DSCEngine_MintFailed();
        }

    }



/* Private functions*/

    function _redeemCollateral(address collateralTokenAddress, uint256 amountWithdrawn, address from, address to) private {

        s_trackCollateralDeposited[from][collateralTokenAddress] -= amountWithdrawn; 
        emit CollateralRedeemed(from, amountWithdrawn, from, to);

        bool success = IERC20(collateralTokenAddress).transfer(to, amountWithdrawn);

        if(!success) {
            revert DSCEngine_transferFailed();
        }
    }

    // from = onBehalfOf
    function _burnDsc(uint256 _amountDscToBurn, address onBehalfOf, address dscFrom) private {

        s_DscMinted[onBehalfOf] -= _amountDscToBurn;   // solidity will throw error if this goes below 0

        bool success = i_dsc.transferFrom(dscFrom, address(this), _amountDscToBurn);

        // This conditional is hypothetically unreachable -- 
        // since IF the  call fails -- then the tx will be reverted from within the transferFrom function
        if(!success) {
            revert DSCEngine_transferFailed();
        }

        i_dsc.burn(_amountDscToBurn);

    }



 /* Private & Internal View & Pure Functions */





    function _getAccountInformation(address _user) private view returns (uint256, uint256) {

        uint256 totalDscMintedByUser = s_DscMinted[_user];
        uint256 collateralValueInUsd = getAccountCollateralValue(_user);

        return (totalDscMintedByUser, collateralValueInUsd);
    }
 
    function _healthFactor(address _user) private view returns(uint256) {

        (uint256 totalDscMintedByUser , uint256 totalCollateralOfUser) = _getAccountInformation(_user);

        return _calculateHealthFactor(totalDscMintedByUser, totalCollateralOfUser);

    }




    function _revertIfHealthFactorIsBroken(address user) internal view {

        uint256 userHealthFactor = _healthFactor(user);

        if(userHealthFactor < MIN_HEALTH_FACTOR) {                          // MIN_HEALTH_FACTOR = 1e18
            revert DSCEngine_BreaksHealthFactor(userHealthFactor);
        }

    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) internal pure returns (uint256) {

        if (totalDscMinted == 0) { 
            return type(uint256).max;    // returns maximum health factor since user has no DSC 
        }
        //type(uint256).max --> returns the maximum value that can be stored in a uint256 variable

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100 ;  // LIQUIDATION_THRESHOLD =50

        /* 
        CASE 1 :
        collateral      = $150 in ETH
        DscMintedSoFar  = $100 
        collateralAdjustedForThreshold = (150 * 50) / 100 => 75
        
        health factor  = 75/100 = 0.75 < 1 => bad health factor   (not allowed to be less than 1)

        CASE 2 :
        collateral      = $1000 in ETH
        DscMintedSoFar  = $100 
        collateralAdjustedForThreshold = (1000 * 50) / 100 => 500        
        
        health factor  = 500/100 = 5 > 1 => Great health factor             
        */

        // multiplying by 1e18 to maintain the return value at 18 decimals
        return (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
    }




 /* External & Public View & Pure Functions */

    function getAccountInformation(address user) external view       
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {

    
        return _getAccountInformation(user);
    }


    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) external pure returns(uint256) {

        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }


    function getAccountCollateralValue(address _user) public view returns(uint256 totalCollateralValueInUsd) {

        for(uint i=0 ; i< s_collateralTokens.length; i++) {

            address tokenAddress = s_collateralTokens[i];
            uint256 tokenAmountHeld = s_trackCollateralDeposited[_user][tokenAddress];
            uint256 tokenValueInUsd = getUsdValue(tokenAddress, tokenAmountHeld);
            totalCollateralValueInUsd += tokenValueInUsd; 
        }

        return totalCollateralValueInUsd;
    }


    function getUsdValue(address _tokenAddress, uint256 _tokenAmountHeld) public view returns(uint256 tokenValueInUsd) {

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenAddress]);

        (  , int256 price, , , ) = priceFeed.latestRoundData();

        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end

        // converting the 36 decimals back to 18 decimals by dividing the result with PRECISION_CONTROL (18 decimals)

        tokenValueInUsd =  ((uint256(price) * PRECISION_10_DECIMALS) * _tokenAmountHeld) / PRECISION_18_DECIMALS; 

    }


    function getTokenAmountFromUsd(address _tokenAddress, uint256 _usdAmountInWei) public view returns(uint256 tokenAmount) {

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenAddress]); 
        (  , int256 price, , , ) = priceFeed.latestRoundData();


        /*
        _usdAmountInWei is 18 decimals
        most price feeds from chainlink has 8 decimals
        We need the return value in 18 decimals */

        tokenAmount = (_usdAmountInWei * PRECISION_18_DECIMALS) / (uint256(price) * PRECISION_10_DECIMALS);
    }  

/* Getter functions*/

    function get18DecimalPrecision() external pure returns(uint256) {

        return PRECISION_18_DECIMALS;
    }

    function get10DecimalPrecision() external pure returns(uint256) {

        return PRECISION_10_DECIMALS;
    }

    function getCollateralBalanceOfUser(address user, address collateralTokenAddress) external view returns(uint256 ) {

        return s_trackCollateralDeposited[user][collateralTokenAddress];
    } 


    function getLiquidationThreshold() external pure returns(uint256) {

        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
     
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns(address[] memory) {

        return s_collateralTokens;
    }

    function getDsc() external view returns (address) { 

        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address collateralTokenAddress) external view returns(address) {

        return s_priceFeeds[collateralTokenAddress];
    }


    function getHealthFactor(address user) external view returns(uint256) {

        return _healthFactor(user);
    }


    function getDscBalanceOfUser(address user) external view returns(uint256) {

        return s_DscMinted[user];
    }

    

}