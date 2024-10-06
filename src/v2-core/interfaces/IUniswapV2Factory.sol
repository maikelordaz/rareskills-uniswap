pragma solidity 0.8.27;

interface IUniswapV2Factory {
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

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}
