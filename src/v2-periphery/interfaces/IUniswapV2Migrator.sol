pragma solidity 0.8.27;

interface IUniswapV2Migrator {
    error UniswapV2Migrator__TransferFromFailed();

    function migrate(
        address token,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external;
}
