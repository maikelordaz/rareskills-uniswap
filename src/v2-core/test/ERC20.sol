pragma solidity 0.8.27;

import {UniswapV2ERC20} from "src/v2-core/UniswapV2ERC20.sol";

contract ERC20 is UniswapV2ERC20 {
    constructor(uint _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}
