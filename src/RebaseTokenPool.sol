//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {TokenPool} from "../lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {console} from "forge-std/Test.sol";
import {Pool} from "../lib/ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {
    IERC20
} from "../lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./Interfaces.sol/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    bytes4 internal constant MINT_SELECTOR = IRebaseToken.mint.selector;
    constructor(IERC20 _token, address[] memory _allowlist, address _rmnProxy, address _router)
        TokenPool(_token, _allowlist, _rmnProxy, _router)
    {}

    //SEPOLIA TO ZKSYNC

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        // console.log("AMOUNT TO BURN ON LOCAL CHAIN: ", lockOrBurnIn.amount);
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        console.log("AMOUNT TO MINT ON REMOTE CHAIN: ", releaseOrMintIn.amount);
        _validateReleaseOrMint(releaseOrMintIn);

        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});

        // _validateReleaseOrMint(releaseOrMintIn);
        // uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        // // --- START OF CONCRETE FIX ---

        // bytes memory callData =
        //     abi.encodeWithSelector(MINT_SELECTOR, releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);

        // // Use try/catch to capture the precise revert reason from the RebaseToken
        // (bool success, bytes memory returnData) = address(i_token).call(callData);

        // if (!success) {
        //     // Log the failure message and re-revert
        //     string memory revertReason = returnData.length > 0 ? abi.decode(returnData, (string)) : "Unknown Revert";

        //     console.log("REMOTE MINT FAILED!");
        //     console.log("Revert Reason:", revertReason);

        //     revert("RebaseTokenPool: Remote Mint Failed (See Logs for Reason)");
        // }

        // // --- END OF CONCRETE FIX ---

        // return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
