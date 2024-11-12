// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {UQ112x112} from "src/clone/libraries/UQ112x112.sol";
import {IUniswapV2Factory} from "src/clone/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Callee} from "src/clone/interfaces/IUniswapV2Callee.sol";

contract UniswapV2Pair is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UQ112x112 for uint224;

    address public factory;
    address public immutable token0;
    address public immutable token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;

    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public constant MINIMUM_LIQUIDITY = 10 ** 3;

    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(
        address indexed sender,
        uint amount0,
        uint amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    error UniswapV2__Forbidden();
    error UniswapV2__InsufficientLiquidityMinted();
    error UniswapV2__InsufficientLiquidityBurned();
    error UniswapV2__InsufficientOutputAmount();
    error UniswapV2__InsufficientLiquidity();
    error UniswapV2__InvalidTo();
    error UniswapV2__InsufficientInputAmount();
    error UniswapV2__K();
    error UniswapV2__Overflow();
    error UniswapV2__TrnasferFailed();

    constructor(address _token0, address _token1) {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    function name() public pure override returns (string memory) {
        return "Uniswap V2";
    }

    function symbol() public pure override returns (string memory) {
        return "UNI-V2";
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint balance0,
        uint balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        require(
            balance0 <= type(uint112).max && balance1 <= type(uint112).max,
            UniswapV2__Overflow()
        );
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed;
        // overflow is desired
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast;
        }
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows
            uint price0CumulativeLastPrev = uint(
                UQ112x112.encode(_reserve1).uqdiv(_reserve0)
            ) * timeElapsed;
            uint price1CumulativeLastPrev = uint(
                UQ112x112.encode(_reserve0).uqdiv(_reserve1)
            ) * timeElapsed;

            // and + overflow is desired
            unchecked {
                price0CumulativeLast += price0CumulativeLastPrev;
                price1CumulativeLast += price1CumulativeLastPrev;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external nonReentrant returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;

        uint _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity =
                FixedPointMathLib.sqrt(amount0 * amount1) -
                MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = FixedPointMathLib.min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }
        require(liquidity > 0, UniswapV2__InsufficientLiquidityMinted());
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        // if (feeOn) kLast = uint(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(
        address to
    ) external nonReentrant returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        IERC20 _token0 = IERC20(token0); // gas savings
        IERC20 _token1 = IERC20(token1); // gas savings
        uint balance0 = _token0.balanceOf(address(this));
        uint balance1 = _token1.balanceOf(address(this));
        uint liquidity = balanceOf(address(this));

        uint _totalSupply = totalSupply();
        amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(
            amount0 > 0 && amount1 > 0,
            UniswapV2__InsufficientLiquidityBurned()
        );
        _burn(address(this), liquidity);
        _token0.safeTransfer(to, amount0);
        _token1.safeTransfer(to, amount1);
        balance0 = _token0.balanceOf(address(this));
        balance1 = _token1.balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        // if (feeOn) kLast = uint(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant {
        require(
            amount0Out > 0 || amount1Out > 0,
            UniswapV2__InsufficientOutputAmount()
        );
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1,
            UniswapV2__InsufficientLiquidity()
        );

        IERC20 _token0 = IERC20(token0);
        IERC20 _token1 = IERC20(token1);

        if (amount0Out > 0) _token0.safeTransfer(to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _token1.safeTransfer(to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) {
            // Todo: Implement flash loan spec, need a flash loan receiver interface
        }

        uint balance0 = _token0.balanceOf(address(this));
        uint balance1 = _token1.balanceOf(address(this));

        uint amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        require(
            amount0In > 0 || amount1In > 0,
            UniswapV2__InsufficientInputAmount()
        );
        // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0 * 1000 - (amount0In * 3);
        uint balance1Adjusted = balance1 * 1000 - (amount1In * 3);
        require(
            balance0Adjusted * balance1Adjusted >=
                uint(_reserve0) * _reserve1 * (1000 ** 2),
            UniswapV2__K()
        );

        _update(balance0, balance1, _reserve0, _reserve1);
        // emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
}
