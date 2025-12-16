//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IRebaseToken} from "./Interfaces.sol/IRebaseToken.sol";

contract Vault {
    // We need to pass the contact address to the constructor
    // create a deposit function that mints tokens to the user equal to the amount of eth the user has sent
    // create a reddem function that burns the tokens from the user and sends the user eth
    // create a way to add rewards to the vault

    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    //Fallbacl funtion to receive eth
    receive() external payable {}

    /**
     * @notice Deposit ETH into the vault and mint Rebase Tokens to the user
     */
    function deposit() external payable {
        // We need to use the amount of eth the user has sent to mint tokens to the user
        //uint256 interestRate = i_rebaseToken.getUserInterestRate(msg.sender);
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeem Rebase Tokens for ETH
     * @param _amount The amount of Rebase Tokens to redeem
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // Burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // Send the user eth equal to the amount of tokens they have burned
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    ///////////////////
    // GETTERS
    ///////////////////

    /**
     * @notice get the address of the rebase token contract
     * @return the address of the rebase token contract
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
