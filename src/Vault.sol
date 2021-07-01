// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "./external/ERC20.sol";
import {CErc20} from "./external/CErc20.sol";
import {StringConcat} from "./libraries/StringConcat.sol";

/// @title Fuse Vault/fvToken
/// @author TransmissionsDev + JetJadeja
/// @notice Yield bearing token that enables users to swap their
/// underlying asset for fvTokens to instantly begin earning yield.
contract Vault is ERC20 {
    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The minimum delay in blocks between each harvest.
    uint256 public constant MIN_HARVEST_DELAY_BLOCKS = 1661;

    /// @notice The underlying token for the vault.
    ERC20 public immutable underlying;

    /// @notice Creates a new vault based on an underlying token.
    /// @param _underlying An underlying ERC20 compliant token.
    constructor(ERC20 _underlying)
        ERC20(
            // ex: Fuse DAI Vault
            StringConcat.concat("Fuse ", _underlying.name(), " Vault"),
            // fvDAI
            StringConcat.concat("fv", _underlying.symbol())
        )
    {
        underlying = _underlying;
    }

    /*///////////////////////////////////////////////////////////////
                             VAULT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice An array of cTokens the Vault holds.
    CErc20[] public depositedPools;

    /// @notice The most recent block where a harvest occured.
    uint256 public lastHarvestBlock;

    /// @notice The amount of "locked" profit acrrued last harvest.
    uint256 public totalLockedProfit;

    /// @notice The total amount of underlying the vault holds (calculated last harvest).
    /// @dev Includes `totalLockedProfit`.
    uint256 public totalUnderlying;

    /*///////////////////////////////////////////////////////////////
                         USER ACTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits an underlying token and mints fvTokens.
    /// @param amount The amount of the underlying token to deposit.
    function deposit(uint256 amount) external {
        //Get the token exchangeRate and underlying decimals
        uint256 exchangeRate = exchangeRateCurrent();
        uint256 decimals = underlying.decimals();

        // Transfer in underlying tokens from the sender.
        underlying.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, (exchangeRate * amount) / 10**decimals);
    }

    /// @notice Burns fvTokens and sends underlying tokens to the sender.
    /// @param amount The amount of fvTokens to burn.
    function withdraw(uint256 amount) external {
        uint256 exchangeRate = exchangeRateCurrent();
        uint256 decimals = underlying.decimals();

        _burn(msg.sender, (amount * 1e36) / (10**decimals / exchangeRate));

        // Transfer underlying tokens to the sender.
        underlying.transfer(msg.sender, amount);
    }

    /*///////////////////////////////////////////////////////////////
                           HARVEST FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function nextHarvest() public view returns (uint256) {
        return MIN_HARVEST_DELAY_BLOCKS + lastHarvestBlock;
    }

    function harvest() external {
        require(block.number >= nextHarvest());

        uint256 newUnderlying;

        // TODO: Optimizations:
        // - Store depositedPools in memory?
        // - Store length on stack?
        // Loop over each pool to add to the total:
        for (uint256 i = 0; i < depositedPools.length; i++) {
            CErc20 pool = depositedPools[i];

            // Add this pool's balance to the total.
            newUnderlying += pool.balanceOfUnderlying(address(this));
        }

        // Locked profit is the delta between the underlying amount we
        // had last harvest and the newly calculated underlying amount.
        totalLockedProfit = newUnderlying - totalUnderlying;

        // Update totalUnderlying to use the freshly computed underlying amount.
        totalUnderlying = newUnderlying;

        // Set the lastHarvestBlock to this block, as we just triggered a harvest.
        lastHarvestBlock = block.number;
    }

    function calculateLockedProfit() public view returns (uint256) {
        uint256 maxLockedProfit = totalLockedProfit;
        uint256 unlockedProfit = (maxLockedProfit * block.number) / nextHarvest();
        return maxLockedProfit - unlockedProfit;
    }

    function calculateTotalFreeUnderlying() public view returns (uint256) {
        return (totalUnderlying + underlying.balanceOf(address(this))) - calculateLockedProfit();
    }

    /*///////////////////////////////////////////////////////////////
                           REBALANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Given a cToken, return a bool indicating whether the vault holds it.
    function haveDepositedInto(CErc20 pool) internal view returns (bool) {
        // TODO: Optimizations:
        // - Store depositedPools in memory?
        // - Store length on stack?
        for (uint256 i = 0; i < depositedPools.length; i++) {
            // If we find the pool that we're entering:
            if (depositedPools[i] == pool) {
                // Exit the function early.
                return true;
            }
        }
        return false;
    }

    /// @dev Deposit into a cErc20 contract
    function enterPool(CErc20 pool, uint256 underlyingAmount) external {
        // If we have not already deposited into the pool:
        if (!haveDepositedInto(pool)) {
            // Push the pool to the depositedPools array.
            depositedPools.push(pool);
        }

        // Approve the underlying to the pool for minting.
        underlying.approve(address(pool), underlyingAmount);

        // Deposit into the pool and receive cTokens.
        pool.mint(underlyingAmount);
    }

    /// @dev Withdraw funds from a cToken contracts
    function exitPool(CErc20 pool, uint256 cTokenAmount) external {
        // If we're withdrawing our full balance:
        uint256 cTokenBalance = pool.balanceOf(address(this));
        if (cTokenBalance == cTokenAmount) {
            // TODO: Optimizations:
            // - Store depositedPools in memory?
            // - Store length on stack?
            // Remove the pool we're withdrawing from:
            for (uint256 i = 0; i < depositedPools.length; i++) {
                // Once we find the pool that we're removing:
                if (depositedPools[i] == pool) {
                    // Move the last item in the array to the index we want to delete.
                    depositedPools[i] = depositedPools[depositedPools.length - 1];

                    // Remove the last index of the array.
                    depositedPools.pop();
                }
            }
        }

        // Withdraw from the pool.
        pool.redeem(cTokenAmount);
    }

    /*///////////////////////////////////////////////////////////////
                         SHARE PRICE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current fvToken exchange rate, scaled by 1e18.
    function exchangeRateCurrent() public view returns (uint256) {
        // Total fvToken supply and vault's total balance in underlying tokens.
        uint256 supply = totalSupply();
        uint256 balance = calculateTotalFreeUnderlying();
        // If either the supply or balance is 0, return 1.
        if (supply == 0 || balance == 0) return 1e18;

        uint256 decimals = underlying.decimals();
        return (balance * 1e36) / (10**decimals * supply);
    }
}
