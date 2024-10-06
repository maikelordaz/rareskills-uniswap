pragma solidity 0.8.27;

import {IUniswapV2Factory} from "src/v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "src/v2-core/interfaces/IUniswapV2Pair.sol";

import {UniswapV2Pair} from "src/v2-core/UniswapV2Pair.sol";

contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair) {
        require(tokenA != tokenB, UniswapV2__IdenticalAddresses());
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), UniswapV2__ZeroAddress());
        require(getPair[token0][token1] == address(0), UniswapV2__PairExists()); // single check is sufficient
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, UniswapV2__Forbidden());
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, UniswapV2__Forbidden());
        feeToSetter = _feeToSetter;
    }
}
