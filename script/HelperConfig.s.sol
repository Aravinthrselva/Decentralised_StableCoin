//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mocks//ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";


contract HelperConfig is Script {


    struct NetworkConfig{
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;    
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 20000e8;
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;


    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {

            activeNetworkConfig = getAnvilConfig();
        }
    }


    function getSepoliaConfig() public view returns(NetworkConfig memory sepoliaNetworkConfig) {

        sepoliaNetworkConfig = NetworkConfig ({
            wethUsdPriceFeed : 0x694AA1769357215DE4FAC081bf1f309aDC325306,  // ETH/USD
            wbtcUsdPriceFeed : 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,  // BTC/USD
            weth             : 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc             : 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey      : vm.envUint("PRV_KEY")
        });

    }


    function getAnvilConfig() public returns(NetworkConfig memory anvilNetworkConfig) {

        // Check to see if we set an active network config
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("Weth", "WETH", msg.sender, 1000e8);

        // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/0a25c1940ca220686588c4af3ec526f725fe2582/contracts/mocks/ERC20Mock.sol
        //name, symbol, initialAccount, initialBalance

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbthMock = new ERC20Mock("Wbtc", "WBTC", msg.sender, 1000e8);

        vm.stopBroadcast();


        anvilNetworkConfig = NetworkConfig ({
            wethUsdPriceFeed : address(ethUsdPriceFeed),  // ETH/USD
            wbtcUsdPriceFeed : address(btcUsdPriceFeed),  // BTC/USD
            weth             : address(wethMock),
            wbtc             : address(wbthMock),
            deployerKey      : DEFAULT_ANVIL_PRIVATE_KEY
        });  
    }

}