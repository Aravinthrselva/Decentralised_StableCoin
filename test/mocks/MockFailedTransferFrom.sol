// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedTransferFrom is ERC20Burnable, Ownable {
    error DStableCoin__AmountMustBeMoreThanZero();
    error DStableCoin__BurnAmountExceedsBalance();
    error DStableCoin__NotZeroAddress();

    /*
    In future versions of OpenZeppelin contracts package, Ownable must be declared with an address of the contract owner as a parameter.
    For example:
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) {}
    Related code changes can be viewed in this commit:
    https://github.com/OpenZeppelin/openzeppelin-contracts/commit/13d5e0466a9855e9305119ed383e54fc913fdc60
    */
    constructor() ERC20("DStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function transferFrom(address, /*sender*/ address, /*recipient*/ uint256 /*amount*/ )
        public
        pure
        override
        returns (bool)
    {
        return false;
    }
}