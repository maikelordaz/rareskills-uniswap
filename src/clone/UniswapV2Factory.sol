// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {UniswapV2Pair} from "src/clone/UniswapV2Pair.sol";

contract UniswapV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint
    );

    error UniswapV2__IdenticalAddresses();
    error UniswapV2__ZeroAddress();
    error UniswapV2__PairExists();
    error UniswapV2__Forbidden();

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address) {
        require(tokenA != tokenB, UniswapV2__IdenticalAddresses());
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), UniswapV2__ZeroAddress());
        require(getPair[token0][token1] == address(0), UniswapV2__PairExists()); // single check is sufficient

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        UniswapV2Pair pair = new UniswapV2Pair{salt: salt}(token0, token1);

        getPair[token0][token1] = address(pair);
        getPair[token1][token0] = address(pair); // populate mapping in the reverse direction
        allPairs.push(address(pair));
        emit PairCreated(token0, token1, address(pair), allPairs.length);

        return address(pair);
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
