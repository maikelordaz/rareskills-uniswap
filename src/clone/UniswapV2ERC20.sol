// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IUniswapV2ERC20} from "src/clone/interfaces/IUniswapV2ERC20.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

contract UniswapV2ERC20 is ERC20 {
    function name() public pure override returns (string memory) {
        return "Uniswap V2";
    }

    function symbol() public pure override returns (string memory) {
        return "UNI-V2";
    }
}
