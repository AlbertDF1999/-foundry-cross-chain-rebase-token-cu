//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IRebaseToken} from "../src/Interfaces.sol/IRebaseToken.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    RebaseToken rebaseToken;
    Vault vault;

    function setUp() public {
        vm.startPrank(owner);
        // Deploy RebaseToken
        rebaseToken = new RebaseToken();
        // Deploy Vault with the address of the RebaseToken
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        //we add some rewards to the vault
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testDeposilLinear(uint256 amount) public {
        //if assume condition does not hold, fuzz test case is discarded, and we want to try as many tests as possible
        //so we will use bound instead of assume
        //vm.assume(amount > 1e4);
        amount = bound(amount, 1e5, type(uint96).max);
        //1.deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        //2. check rebase balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("Start balance:", startBalance);
        assertEq(startBalance, amount);
        //3. warp time and check balance again
        vm.warp(block.timestamp + 1 hours);
        // rebaseToken.transfer(user, 0);
        console.log("block.timestamp", block.timestamp);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("Middle balance after 1 hour:", middleBalance);
        assertGt(middleBalance, startBalance);
        //4. warp more time by the same amount and check balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 finalBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("Final balance after 2 hours:", finalBalance);
        assertGt(finalBalance, middleBalance);

        assertApproxEqAbs(finalBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        // 1-deposit
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        //2-redeem
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testUserCanRedeemAfterSomeTime(uint256 amount, uint256 time) public {
        time = bound(time, 3000, type(uint96).max);
        //1 deposit
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        //2 warp time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);

        //2 (b) add rewards to the vault
        vm.deal(owner, balanceAfterSomeTime - amount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - amount);

        //3 redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, amount);
    }

    function testTransferAndInterestIsInherited(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        //1 deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 initialBalanceUser1 = rebaseToken.balanceOf(user);
        uint256 initialBalanceUser2 = rebaseToken.balanceOf(user2);
        assertEq(initialBalanceUser1, amount);
        assertEq(initialBalanceUser2, 0);

        //owner reduces interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        //2 transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 user1BalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(user1BalanceAfterTransfer, initialBalanceUser1 - amountToSend);
        assertEq(user2BalanceAfterTransfer, initialBalanceUser2 + amountToSend);

        //check the interest rate has been inherited (5e14 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user2), rebaseToken.getUserInterestRate(user));
    }

    function testUserCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testUserCannotMintOrBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 1000);
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, 1000);
    }

    function testGetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        //1 deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        uint256 principleAmount = rebaseToken.getPrincipleBalanceOf(user);
        assertEq(principleAmount, amount);

        //2 warp time
        vm.warp(block.timestamp + 1 hours);
        uint256 principleAmountAfterTime = rebaseToken.getPrincipleBalanceOf(user);
        assertEq(principleAmountAfterTime, amount);
    }

    function testGetRebaseTokenAddress() public {
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        assertEq(rebaseTokenAddress, address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
