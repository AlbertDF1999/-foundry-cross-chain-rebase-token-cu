//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Rebase Token
 * @author Alberto Castro
 * @notice This is going to be a cross chain token that incentivises users to deposit into a vault
 * @notice The interest rate in the smart contract can only decrease
 * @notice each user will have their own interest rate that is the global interest rate at the time of depositing
 *
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    ///////////////////
    // ERRORS
    ///////////////////
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    ///////////////////
    // STATE VARIABLES
    ///////////////////
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = 5e14; //(5 * PRECISION_FACTOR) / 1e8; //10^-8 == 1 = 1/10^8. previous value was 5e10
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    ///////////////////
    // EVENTS
    ///////////////////
    event InterestRateSet(uint256 newInterestRate);

    ///////////////////
    // CONSTRUCTOR
    ///////////////////
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice set the interest rate in the contract
     * @param _newInterestRate is the new interest rate to set
     * @dev the interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        //set new interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;

        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice get the principle balance of the user (the amount of tokens that have actually been minted to the user), not including any accrued interest
     * @notice since the last time the user interacted with the protocol
     * @param _user the address of the user to get the principle balance of
     * @return the principle balance of the user
     */

    /**
     * @notice mint the user tokens when they deposit into the vault
     * @param _to the address to mint the tokens to
     * @param _amount the amount of tokens to mint
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice burn the user tokens when they withdraw from the vault
     * @param _from the address to burn the tokens from
     * @param _amount the amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice this balanceOf function will return the balance in the ERC20 contract called _balances plus any interest that has accrued
     * @notice since the last time the last interest was minted to the user, since the last time they performed any action.
     * @param _user the address of the user to get the balance of\
     * @return the balance of the user including any accrued interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //get the current principle balance of the user (the number of tokens that have actually benn minted to the user)
        //multiply the principle balance by the interest that has accumulated in the time since the balance was last updated
        uint256 principleBalance = super.balanceOf(_user);
        if (principleBalance == 0) {
            return 0;
        }
        return principleBalance * _calculateAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     *
     * @notice transfer tokens from one address to another
     * @param _recipient the address to tranfer tokens to
     * @param _amount the amount of tokens to transfer
     * @return true if the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        //accummulates the balance of the user so it is up to date with any interest that has accrued
        if (_amount == type(uint256).max) {
            _amount = super.balanceOf(msg.sender);
        }
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice transfer tokens from one address to another
     * @param _sender the address to transfer tokens from
     * @param _recipient the address to transfer tokens to
     * @param _amount the amount of tokens to transfer
     * @return true if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        if (_amount == type(uint256).max) {
            _amount = super.balanceOf(_sender);
        }
        // accumulates the balance of the user so it is up to date with any interest accumulated.
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice calculate the accumulated interest since the last time the user was updated
     * @param _user the address of the user to calculate the accumulated interest for
     * @return linearInterest the interest that has accumulated since the last time the user was updated
     */
    function _calculateAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        //this is going to be linear growth with time
        // 1 calculate the time since last update
        // 2 calculate the amount of linear growth
        // principle amount + (pricipal amount * interest rate * time elapsed) or principle amount (1 + (interest rate * time elapsed))
        //deposit: 10 tokens
        //interest rate: 0.5 % per second
        //time elapsed: 2 seconds
        //10 + (10 * 0.5 * 2)
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        //linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed) / 1e18;
        linearInterest = (s_userInterestRate[_user] * timeElapsed) + PRECISION_FACTOR;
    }

    /**
     * @notice mint the accrued interest to the user since the last time they interacted with the protocol(e.g. burn, mint, transfer)
     * @param _user the address of the user to mint the interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user => principle balance
        uint256 previousprincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> total balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousprincipleBalance;
        // call _mint to mint the interest tokens to the user
        _mint(_user, balanceIncrease);
        // set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    ///////////////////
    // GETTERS
    ///////////////////

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice get the global interest rate in the contract
     * @return the global interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getPrincipleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }
}
