// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract UniswapV2Pair is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint public constant MINIMUM_LIQUIDITY = 1_000;
    uint256 private constant DECIMAL_MULTIPLIER = 1_000;
    uint256 private constant FEE_MULTIPLIER = 997;
    bytes32 private constant FLASHSWAP_CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    string public constant NAME = "Uniswap V2";
    string public constant SYMBOL = "UNI-V2";

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 private _reserve0;
    uint112 private _reserve1;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    uint32 private _blockTimestampLast;

    event Mint(address indexed sender, uint amount0, uint amount1, uint shares);
    event Burn(
        address indexed sender,
        uint amount0,
        uint amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        bool indexed side,
        uint amountIn,
        uint amountOut,
        address indexed to
    );

    error UniswapV2__InsufficientInputAmount();
    error UniswapV2__Overflow();
    error UniswapV2__InsufficientBalance();
    error UniswapV2Pair__FlashSwapExceedsMaxRepayment();
    error UniswapV2Pair__FlashSwapReceiverFailure();
    error UniswapV2Pair__FlashSwapNotPaidBack();
    error UniswapV2_Pair__SwapDoesNotMeetMinimumOut();

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function name() public pure override returns (string memory) {
        return NAME;
    }

    function symbol() public pure override returns (string memory) {
        return SYMBOL;
    }

    /// @notice Add liquidity to the pool by transferring tokens in
    /// @dev emits a Mint event
    /// @param amount0Approved Max amount of token0 the sender is willing to transfer out of their account
    /// @param amount1Approved Max amount of token1 the sender is willing to transfer out of their account
    /// @param amount0Min Min amount of token0 the sender is willing to transfer out of their account
    /// @param amount1Min Min amount of token01the sender is willing to transfer out of their account
    /// @param to Address to mint liquidity tokens to
    function addLiquidity(
        uint256 amount0Approved,
        uint256 amount1Approved,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external nonReentrant {
        uint256 totalSupply_ = totalSupply();
        IERC20 _token0 = token0;
        IERC20 _token1 = token1;

        if (totalSupply_ == 0) {
            _token0.safeTransferFrom(
                msg.sender,
                address(this),
                amount0Approved
            );
            _token1.safeTransferFrom(
                msg.sender,
                address(this),
                amount1Approved
            );
            uint256 shares = FixedPointMathLib.sqrt(
                amount0Approved * amount1Approved
            ) - MINIMUM_LIQUIDITY;
            _mint(to, shares);
            emit Mint(msg.sender, amount0Approved, amount1Approved, shares);
            _mint(address(0), MINIMUM_LIQUIDITY);
            emit Mint(
                address(0),
                amount0Approved,
                amount1Approved,
                MINIMUM_LIQUIDITY
            );
            _updateReserves(
                _token0.balanceOf(address(this)),
                _token1.balanceOf(address(this)),
                0,
                0
            );
            return;
        }

        uint112 reserve0_ = _reserve0;
        uint112 reserve1_ = _reserve1;
        uint256 amount1ImpliedByApproval = (reserve1_ * amount0Approved) /
            reserve0_;
        uint256 amount0ToUse;
        uint256 amount1ToUse;
        if (amount1ImpliedByApproval > amount1Approved) {
            amount0ToUse = (reserve0_ * amount1Approved) / reserve1_;

            require(
                amount0ToUse > amount0Min,
                UniswapV2__InsufficientInputAmount()
            );

            amount1ToUse = amount1Approved;
        } else {
            amount1ToUse = amount1ImpliedByApproval;
            require(
                amount1ToUse > amount1Min,
                UniswapV2__InsufficientInputAmount()
            );
            amount0ToUse = amount0Approved;
        }

        uint256 initialBalance0 = _token0.balanceOf(address(this));
        _token0.safeTransferFrom(msg.sender, address(this), amount0ToUse);
        uint256 actualAmount0;
        unchecked {
            // Pair balance can only increase
            actualAmount0 = _token0.balanceOf(address(this)) - initialBalance0;
        }

        uint256 initialBalance1 = _token1.balanceOf(address(this));
        _token1.safeTransferFrom(msg.sender, address(this), amount1ToUse);

        uint256 actualAmount1;
        unchecked {
            // Pair balance can only increase
            actualAmount1 = _token1.balanceOf(address(this)) - initialBalance1;
        }

        unchecked {
            // Unchecked as the balance of this contract could not overflow, as otherwise the total supply of token0
            // or token1 would have to overlfow
            _updateReserves(
                reserve0_ + actualAmount0,
                reserve1_ + actualAmount1,
                reserve0_,
                reserve1_
            );
        }
        uint256 liquidity0 = (actualAmount0 * totalSupply_) / reserve0_;
        uint256 liquidity1 = (actualAmount1 * totalSupply_) / reserve1_;
        if (liquidity0 < liquidity1) {
            _mint(to, liquidity0);
            emit Mint(msg.sender, actualAmount0, actualAmount1, liquidity0);
        } else {
            _mint(to, liquidity1);
            emit Mint(msg.sender, actualAmount0, actualAmount1, liquidity1);
        }
    }

    /// @notice Remove liquidity from the Pair
    /// @dev emits a Burn event
    /// @dev reverts if the sender does not have sufficient balance
    /// @param liquidity Number of liquidity tokens to withdraw
    /// @param amount0Min Minimum amount of token0 the user is willing to receive
    /// @param amount1Min Minimum amount of token1 the user is willing to receive
    /// @param to Address to receive token0 and token1
    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external nonReentrant {
        uint256 balance = balanceOf(msg.sender);
        require(balance > liquidity, UniswapV2__InsufficientBalance());

        uint256 totalSupply_ = totalSupply();
        IERC20 _token0 = token0;
        uint256 amount0 = (liquidity * _token0.balanceOf(address(this))) /
            totalSupply_;
        require(amount0 > amount0Min, UniswapV2__InsufficientInputAmount());

        IERC20 _token1 = token1;
        uint256 amount1 = (liquidity * _token1.balanceOf(address(this))) /
            totalSupply_;
        require(amount1 > amount1Min, UniswapV2__InsufficientInputAmount());

        _burn(msg.sender, liquidity);
        _token0.safeTransfer(to, amount0);
        _token1.safeTransfer(to, amount1);

        uint112 reserve0_ = _reserve0;
        uint112 reserve1_ = _reserve1;

        unchecked {
            // Unchecked is safe as the user can't withdraw more than our reserves
            _updateReserves(
                reserve0_ - amount0,
                reserve1_ - amount1,
                reserve0_,
                reserve1_
            );
        }

        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @notice Flash swap one token for the other token: `to` receives the requested amount of tokens first, after
    /// which their callback function will be invoked which must repay the required quantity of the other token.
    /// @dev `to` must implement `IERC3156FlashBorrower`
    /// @dev emits a Swap event
    /// @dev reverts if `to` does not pay back at least the required value of tokens
    /// @param side If true, then the swap is from token1 to token0, otherwise the swap is from token0 to token1
    /// @param amount Amount of tokens to transfer out of the Pair
    /// @param maxRepayment Maximum number of tokens the caller is willing to use to payback the Pair
    /// @param to Address to receive the tokens
    function flashSwap(
        bool side,
        uint256 amount,
        uint256 maxRepayment,
        address to
    ) external nonReentrant {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint112 reserveIn;
        uint112 reserveOut;
        if (side) {
            tokenIn = token1;
            tokenOut = token0;
            reserveIn = _reserve1;
            reserveOut = _reserve0;
        } else {
            tokenIn = token0;
            tokenOut = token1;
            reserveIn = _reserve0;
            reserveOut = _reserve1;
        }

        uint256 initialToBalanceOut = tokenOut.balanceOf(to);
        tokenOut.safeTransfer(to, amount);
        uint256 actualAmount = initialToBalanceOut - tokenOut.balanceOf(to);
        uint256 initialBalanceIn = tokenIn.balanceOf(address(this));
        uint256 owedIn = (DECIMAL_MULTIPLIER * amount * reserveIn) /
            (FEE_MULTIPLIER * (reserveOut - amount));
        require(
            owedIn < maxRepayment,
            UniswapV2Pair__FlashSwapExceedsMaxRepayment()
        );

        bytes32 callbackResult = IERC3156FlashBorrower(to).onFlashLoan(
            msg.sender,
            address(tokenOut),
            actualAmount,
            0,
            abi.encodePacked(tokenIn, owedIn) // Tell the flash borrower what token they owe back and how much
        );
        require(
            callbackResult == FLASHSWAP_CALLBACK_SUCCESS,
            UniswapV2Pair__FlashSwapReceiverFailure()
        );

        uint256 finalBalanceIn = tokenIn.balanceOf(address(this));
        unchecked {
            // Pair balance dont decrease
            require(
                finalBalanceIn - initialBalanceIn > owedIn,
                UniswapV2Pair__FlashSwapNotPaidBack()
            );
        }

        if (side) {
            _updateReserves(
                tokenOut.balanceOf(address(this)),
                finalBalanceIn,
                reserveOut,
                reserveIn
            );
        } else {
            _updateReserves(
                finalBalanceIn,
                tokenOut.balanceOf(address(this)),
                reserveIn,
                reserveOut
            );
        }

        emit Swap(msg.sender, side, owedIn, amount, to);
    }

    /// @notice Swap one token for the other token
    /// @dev emits a Swap event
    /// @dev reverts if sender has not already approved at least `amountIn`
    /// @param side If true, then the swap is from token1 to token0, otherwise the swap is from token0 to token1
    /// @param amountIn Amount of tokens to transfer out of the sender's account
    /// @param amountOutMin Minimum number of tokens the user is willing to receive in return
    /// @param to Address to receive the tokens
    function swapExactTokenForToken(
        bool side,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external nonReentrant {
        IERC20 inToken;
        uint112 inReserve;
        IERC20 outToken;
        uint112 outReserve;

        if (side) {
            inToken = token1;
            inReserve = _reserve1;
            outToken = token0;
            outReserve = _reserve0;
        } else {
            inToken = token0;
            inReserve = _reserve0;
            outToken = token1;
            outReserve = _reserve1;
        }

        uint256 initialBalanceIn = inToken.balanceOf(address(this));
        uint256 initialBalanceOut = outToken.balanceOf(address(this));
        inToken.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 finalBalanceIn = inToken.balanceOf(address(this));
        uint256 actualAmountIn;
        unchecked {
            actualAmountIn = finalBalanceIn - initialBalanceIn;
        }
        uint256 actualAmountInSubFee = actualAmountIn * FEE_MULTIPLIER;

        uint256 amountOut = (actualAmountInSubFee * outReserve) /
            (inReserve * DECIMAL_MULTIPLIER + actualAmountInSubFee);
        require(
            amountOut > amountOutMin,
            UniswapV2_Pair__SwapDoesNotMeetMinimumOut()
        );

        outToken.safeTransfer(to, amountOut);
        uint256 finalBalanceOut = outToken.balanceOf(address(this));

        unchecked {
            if (side) {
                _updateReserves(
                    outReserve - amountOut,
                    inReserve + actualAmountIn,
                    outReserve,
                    inReserve
                );
            } else {
                _updateReserves(
                    inReserve + actualAmountIn,
                    outReserve - amountOut,
                    inReserve,
                    outReserve
                );
            }
        }

        emit Swap(msg.sender, side, amountIn, amountOut, to);
    }

    function _updateReserves(
        uint256 newReserve0,
        uint256 newReserve1,
        uint112 currentReserve0,
        uint112 currentReserve1
    ) private {
        require(
            newReserve0 < type(uint112).max && newReserve1 < type(uint112).max,
            UniswapV2__Overflow()
        );

        uint32 currentBlockTimestamp = uint32(block.timestamp % 2 ** 32);
        unchecked {
            uint32 timeSinceLastUpdate = currentBlockTimestamp -
                _blockTimestampLast;
            if (
                timeSinceLastUpdate > 0 &&
                currentReserve0 != 0 &&
                currentReserve1 != 0
            ) {
                price0CumulativeLast +=
                    uint256(
                        _asFixedPoint112(currentReserve1) /
                            uint224(currentReserve0)
                    ) *
                    timeSinceLastUpdate;
                price1CumulativeLast +=
                    uint256(
                        _asFixedPoint112(currentReserve0) /
                            uint224(currentReserve1)
                    ) *
                    timeSinceLastUpdate;
            }
        }
        _blockTimestampLast = currentBlockTimestamp;
        _reserve0 = uint112(newReserve0);
        _reserve1 = uint112(newReserve1);
    }

    function _asFixedPoint112(uint112 x) private pure returns (uint224) {
        return uint224(x) << 112;
    }
}
