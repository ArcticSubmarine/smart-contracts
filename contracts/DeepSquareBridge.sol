// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./Eligibility.sol";

/**
 * @title Swapper for DPS and Square tokens.
 * @author Mathieu Bour, Julien Schneider, Charly Mancel, Valentin Pollart and Clarisse Tarrou for the DeepSquare Association.
 */
contract DeepSquareBridge is Ownable {
    /// @notice The DPS token contract.
    IERC20Metadata public immutable DPS;

    /// @notice The SQA token contract.
    IERC20Metadata public immutable SQA;

    // @notice The eligibility contract.
    IEligibility public immutable eligibility;

    // @notice The minimum amount of token the user has to possess in order to swap (= user's number of DPS + user's number of SQA).
    uint256 public immutable minRequiredToSwap;

    /**
     * Token purchase event.
     * @param investor The investor address.
     * @param amountDPS Amount of DPS tokens purchased.
     */
    event SwapSQAToDPS(address indexed investor, uint256 amountDPS);

    /**
     * Token purchase event.
     * @param investor The investor address.
     * @param amountSQA Amount of SQA tokens purchased.
     */
    event SwapDPSToSQA(address indexed investor, uint256 amountSQA);

    /**
     * @param _DPS The DPS contract address.
     * @param _SQA The ERC20 stablecoin contract address (e.g, USDT, USDC, etc.).
     * @param _eligibility The eligibility contract.
     * @param _minRequiredToSwap The minimum amount of token the user has to possess in order to swap (= user's number of DPS + user's number of SQA).
     */
    constructor(
        IERC20Metadata _DPS,
        IERC20Metadata _SQA,
        Eligibility _eligibility,
        uint256 _minRequiredToSwap
    ) {
        require(address(_DPS) != address(0), "DeepSquareBridge: token is zero");
        require(address(_SQA) != address(0), "DeepSquareBridge: stablecoin is zero");
        require(address(_eligibility) != address(0), "DeepSquareBridge: eligibility is zero");
        require(_minRequiredToSwap > 0, "DeepSquareBridge: min required to swap is not positive");

        DPS = _DPS;
        SQA = _SQA;
        eligibility = _eligibility;
        minRequiredToSwap = _minRequiredToSwap;
    }

    /**
     * @notice Get the remaining DPS tokens to swap.
     * @return The amount of DPS remaining in the swapper.
     */
    function remainingDPS() external view returns (uint256) {
        return DPS.balanceOf(address(this));
    }

    /**
     * @notice Get the remaining SQA tokens to swap.
     * @return The amount of SQA remaining in the swapper.
     */
    function remainingSQA() external view returns (uint256) {
        return SQA.balanceOf(address(this));
    }

    /**
     * @notice Validate that the account is allowed to swap DPS and SQA.
     * @dev Requirements:
     * - the account sum of DPS and SQA is greater than minRequiredToSwap.
     * - the account is eligible.
     * @param account The account to check that should receive the DPS.
     */
    function _validate(address account) internal returns (uint256) {
        require(
            SQA.balanceOf(account) + DPS.balanceOf(account) >= minRequiredToSwap,
            "DeepSquareBridge: the account does not have sufficient provision"
        );

        (uint8 tier, uint256 limit) = eligibility.lookup(account);

        require(tier > 0, "DeepSquareBridge: account is not eligible");

        // Eligibility limit in DPS.
        return limit;
    }

    /**
     * @notice Deliver the DPS to the account.
     * @dev Requirements:
     * - there are enough DPS remaining in the sale.
     * @param account The account that will receive the DPS.
     * @param amount The amount of DPS to transfer.
     */
    function _transferDPS(address account, uint256 amount) internal {
        _validate(account);
        DPS.transfer(account, amount);
    }

    /**
     * @notice Deliver the SQA to the account.
     * @dev Requirements:
     * - there are enough SQA remaining.
     * @param account The account that will receive the SQA.
     * @param amount The amount of SQA to transfer.
     */
    function _transferSQA(address account, uint256 amount) internal {
        _validate(account);
        SQA.transfer(account, amount);
    }

    /**
     * @notice Buy DPS with stablecoins.
     * @param amount The amount of stablecoin to invest.
     */
    function swapSQAToDPS(address account, uint256 amount) external {
        require(amount > 0, "DeepSquareBridge: amount is not greater than 0");
        // Purchase limit from the eligibility.
        uint256 limit = _validate(msg.sender);

        uint256 investment = DPS.balanceOf(account) + amount;

        if (limit != 0) {
            // zero limit means that the tier has no restrictions
            require(investment < limit, "DeepSquareBridge: exceeds tier limit");
        }

        uint256 availableDPS = DPS.balanceOf(address(this));
        require(availableDPS >= amount, "DeepSquareBridge: not enough remaining DPS");

        SQA.transferFrom(msg.sender, address(this), amount);
        _transferDPS(msg.sender, amount);
        emit SwapSQAToDPS(account, amount);
    }

    /**
     * @notice Buy stablecoins with DPS.
     * @param amount The amount of DPS to invest.
     */
    function swapDPSToSQA(uint256 amount) external {
        require(amount > 0, "DeepSquareBridge: amount is not greater than 0");
        // Purchase limit from the eligibility.
        uint256 limit = _validate(msg.sender);

        uint256 investment = DPS.balanceOf(msg.sender) + amount;

        if (limit != 0) {
            // zero limit means that the tier has no restrictions
            require(investment < limit, "DeepSquareBridge: exceeds tier limit");
        }

        uint256 availableSQA = SQA.balanceOf(address(this));
        require(availableSQA >= amount, "DeepSquareBridge: not enough remaining DPS");

        DPS.transferFrom(msg.sender, owner(), amount);
        _transferSQA(msg.sender, amount);
        emit SwapDPSToSQA(msg.sender, amount);
    }
}
