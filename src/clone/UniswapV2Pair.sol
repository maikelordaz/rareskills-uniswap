// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC3156FlashBorrower, IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {UD60x18, ud} from "prb-math/UD60x18.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UniswapV2Pair is ERC20, ReentrancyGuard, IERC3156FlashLender {
    using SafeERC20 for IERC20;

    uint public constant MINIMUM_LIQUIDITY = 1_000;
    uint256 private constant FEE = 30;

    string public constant NAME = "Uniswap V2";
    string public constant SYMBOL = "UNI-V2";
    bytes32 private constant FLASHSWAP_CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    address public immutable factory;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    error UniswapV2Pair__ZeroAddress();
    error UniswapV2Pair__UnsupportedToken();
    error UniswapV2Pair__FlashLoanFailed();
    error UniswapV2Pair__Overflow();
    error UniswapV2Pair__MinimumLiquidity();
    error UniswapV2Pair__InsufficientLiquidity();
    error UniswapV2Pair__ZeroOutput();
    error UniswapV2Pair__InsufficientReserve();
    error UniswapV2Pair__ZeroInput();
    error UniswapV2Pair__XYK();

    constructor(address _token0, address _token1) {
        require(
            _token0 != address(0) && _token1 != address(0),
            UniswapV2Pair__ZeroAddress()
        );
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        factory = msg.sender;
    }

    /**
     * @notice IERC3156FlashLender-{flashLoan}
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) public override returns (bool) {
        IERC20 token0_ = token0; // copy into memory

        require(
            token == address(token0_) || token == address(token1),
            UniswapV2Pair__UnsupportedToken()
        );
        // lend token. It would fail if amount > reserve
        IERC20(token).safeTransfer(address(receiver), amount);

        uint256 fee;
        unchecked {
            // cannot overflow
            fee = (amount * FEE) / 10_000;
        }
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) ==
                FLASHSWAP_CALLBACK_SUCCESS,
            UniswapV2Pair__FlashLoanFailed()
        );

        // receive token amount + fee
        IERC20(token).safeTransferFrom(
            address(receiver),
            address(this),
            amount + fee
        );

        unchecked {
            // update reserves: cannot overflow
            if (token == address(token0_)) {
                _reserve0 += uint112(fee);
            } else {
                _reserve1 += uint112(fee);
            }
        }
        return true;
    }

    /**
     * @dev function to call for supplying liquidity to the pool
     * @param to address to receive new liquidity tokens
     * @return liquidity amount of liquidity tokens to send to `to` address
     * This function expects to receive required amount of tokens to make the mint possible.
     */
    function mint(address to) public nonReentrant returns (uint256 liquidity) {
        // check for balance amounts and make sure they dont overflow uint112
        (uint112 res0, uint112 res1) = (_reserve0, _reserve1); // copy into memory
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 liquiditySupply = totalSupply(); // copy into memory

        require(
            balance0 < type(uint112).max || balance1 < type(uint112).max,
            UniswapV2Pair__Overflow()
        );

        unchecked {
            // calculate user deposits, can't overflow
            balance0 -= uint256(res0);
            balance1 -= uint256(res1);
        }

        if (liquiditySupply == 0) {
            // when adding liquidity for the first time: liquidity = sqrt(balance0 * balance1)
            liquidity = FixedPointMathLib.sqrt(balance0 * balance1);
            require(
                liquidity > MINIMUM_LIQUIDITY,
                UniswapV2Pair__MinimumLiquidity()
            );
            // mint to address(1) since minting to address(0) required overriding mint function
            _mint(address(1), MINIMUM_LIQUIDITY);

            unchecked {
                liquidity -= MINIMUM_LIQUIDITY;
            }
        } else {
            // in case deposits are not in correct proportions, compare ratios
            UD60x18 ratio0 = ud(balance0).div(ud(res0));
            UD60x18 ratio1 = ud(balance1).div(ud(res1));

            // cannot overflow since liquidity is bound to uint256
            if (ratio0 < ratio1) {
                liquidity = (balance0 * liquiditySupply) / res0;
                balance1 = (res1 * balance0) / res0;
            } else {
                liquidity = (balance1 * liquiditySupply) / res1;
                balance0 = (res0 * balance1) / res1;
            }
        }

        require(liquidity != 0, UniswapV2Pair__InsufficientLiquidity());

        unchecked {
            // update reserves. cant overflow
            _reserve0 = res0 + uint112(balance0);
            _reserve1 = res1 + uint112(balance1);
        }
        (res0, res1) = (_reserve0, _reserve1); // copy into memory

        // update cumulative prices
        _updateCumulativePrices(res0, res1);

        _mint(to, liquidity);

        emit Mint(to, balance0, balance1);
        emit Sync(res0, res1);
    }

    /**
     * @dev function to call when removing liquidity from the pool
     * @param to address to receive the removed asset
     * @return amount0 amount of token0 to send to `to` address
     * @return amount1 amount of token1 to send to `to` address
     * This function expects to receive required amount of tokens to make the burn possible.
     */
    function burn(
        address to
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 res0, uint112 res1) = (_reserve0, _reserve1); // copy into memory

        uint256 burnAmount = balanceOf(address(this));

        uint256 liquiditySupply = totalSupply(); // copy into memory

        unchecked {
            // cant overflow because uint112 * uint112 / uint256
            amount0 = (res0 * burnAmount) / liquiditySupply;
            amount1 = (res1 * burnAmount) / liquiditySupply;
        }

        unchecked {
            // update reserves. cant overflow
            _reserve0 = res0 - uint112(amount0);
            _reserve1 = res1 - uint112(amount1);
        }
        (res0, res1) = (_reserve0, _reserve1); // copy into memory

        // update cumulative prices
        _updateCumulativePrices(res0, res1);

        _burn(address(this), burnAmount);
        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        emit Burn(to, amount0, amount1, to);
        emit Sync(res0, res1);
    }

    /**
     * @dev swap function to trade between tokens
     * @param amount0Out expected amount of token0 to receive
     * @param amount1Out expected amount of token1 to receive
     * @param to address to receive the out tokens
     * This function expects to receive required amount of tokens to make the trade possible.
     */
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata
    ) external nonReentrant {
        require(
            amount0Out != 0 || amount1Out != 0,
            UniswapV2Pair__ZeroOutput()
        );
        (uint112 res0, uint112 res1) = (_reserve0, _reserve1); // copy into memory
        require(
            amount0Out < res0 && amount1Out < res1,
            UniswapV2Pair__InsufficientReserve()
        );

        // check for balances
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        require(
            balance0 < type(uint112).max && balance1 < type(uint112).max,
            UniswapV2Pair__Overflow()
        );

        uint256 amount0In;
        uint256 amount1In;
        {
            unchecked {
                if (balance0 > res0) {
                    amount0In = balance0 - res0;
                }
                if (balance1 > res1) {
                    amount1In = balance1 - res1;
                }
            }

            require(
                amount0In != 0 || amount1In != 0,
                UniswapV2Pair__ZeroInput()
            );
            uint256 actualTransfer0Out;
            uint256 actualTransfer1Out;
            unchecked {
                // deduct fee from transfer outs and then re-calculate. Wont overflow.
                actualTransfer0Out = amount0Out - (amount0Out * FEE) / 10_000;
                actualTransfer1Out = amount1Out - (amount1Out * FEE) / 10_000;

                // update reserves
                _reserve0 =
                    (res0 + uint112(amount0In)) -
                    uint112(actualTransfer0Out);
                _reserve1 =
                    (res1 + uint112(amount1In)) -
                    uint112(actualTransfer1Out);

                // check if xy=k holds true. Lte to allow amount0In >= actualAmount0In
                require(
                    uint256(_reserve0) * uint256(_reserve1) >=
                        uint256(res0) * uint256(res1),
                    UniswapV2Pair__XYK()
                );
            }

            (res0, res1) = (_reserve0, _reserve1);
            // make transfers
            IERC20(token0).safeTransfer(to, actualTransfer0Out);
            IERC20(token1).safeTransfer(to, actualTransfer1Out);
        }

        // update cumulative prices
        _updateCumulativePrices(res0, res1);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        emit Sync(res0, res1);
    }

    /**
     * @dev function to withdraw amont of tokens exceeding the reserve values
     */
    function skim(address to) external {
        uint256 diff0;
        uint256 diff1;
        unchecked {
            // cant overflow
            diff0 = token0.balanceOf(address(this)) - _reserve0;
            diff1 = token1.balanceOf(address(this)) - _reserve1;
        }

        token0.safeTransfer(to, diff0);
        token1.safeTransfer(to, diff1);
    }

    /**
     * @dev function to sync reserves to the token balances of the pool
     */
    function sync() external {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        require(
            balance0 < type(uint112).max && balance1 < type(uint112).max,
            UniswapV2Pair__Overflow()
        );

        // update reserves
        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        (uint112 r0, uint112 r1) = (_reserve0, _reserve1); // copy into memory

        // update cumulative prices
        _updateCumulativePrices(r0, r1);

        emit Sync(r0, r1);
    }

    function name() public pure override returns (string memory) {
        return NAME;
    }

    function symbol() public pure override returns (string memory) {
        return SYMBOL;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function kLast() public view returns (uint256) {
        return uint256(_reserve0) * uint256(_reserve1);
    }

    /**
     * @notice IERC3156FlashLender-{maxFlashLoan}
     * @param token address of token to borrow
     * @return amount maximum that user can borrow
     */
    function maxFlashLoan(
        address token
    ) public view override returns (uint256 amount) {
        require(
            token == address(token0) || token == address(token1),
            UniswapV2Pair__UnsupportedToken()
        );
        amount = token == address(token0) ? _reserve0 : _reserve1;
    }

    /**
     * @param token address of token to borrow
     * @param amount amount of the token to borrow
     * @return fee for flashloan
     */
    function flashFee(
        address token,
        uint256 amount
    ) public view override returns (uint256 fee) {
        require(
            token == address(token0) || token == address(token1),
            UniswapV2Pair__UnsupportedToken()
        );
        fee = (amount * FEE) / 10_000;
    }

    /**
     * @dev private function to update cumulative prices for TWAP purposes
     */
    function _updateCumulativePrices(uint112 _res0, uint112 _res1) private {
        uint32 timeElapsed;
        unchecked {
            timeElapsed =
                uint32(block.timestamp % 2 ** 32) -
                _blockTimestampLast;
            // its okay for _blockTimestampLast to overflow
            _blockTimestampLast = uint32(block.timestamp % 2 ** 32);
        }
        uint256 price0CumulativeLastPrev = UD60x18.unwrap(
            ud(_res1).div(ud(_res0))
        ) * timeElapsed;
        uint256 price1CumulativeLastPrev = UD60x18.unwrap(
            ud(_res0).div(ud(_res1))
        ) * timeElapsed;

        unchecked {
            price0CumulativeLast += price0CumulativeLastPrev;
            price1CumulativeLast += price1CumulativeLastPrev;
        }
    }
}
