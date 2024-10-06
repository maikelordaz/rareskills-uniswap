pragma solidity 0.8.27;

import {IUniswapV2ERC20} from "src/interfaces/IUniswapV2ERC20.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

contract UniswapV2ERC20 is ERC20 {
    function name() public pure override returns (string memory) {
        return "Uniswap V2";
    }

    function symbol() public pure override returns (string memory) {
        return "UNI-V2";
    }
}
