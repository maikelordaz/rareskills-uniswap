## Uniswap assignment

Deliverables:
- [ ]  Re-implement Uniswap V2 with the following requirements. Find it in `src/clone` folder
- use solidity 0.8.0 or higher. **You need to be conscious of when the original implementation originally intended to overflow in the oracle**
- Use the Solady ERC20 library to accomplish the LP token, also use the Solady library to accomplish the square root
- The uniswap re-entrancy lock is not gas efficient anymore because of changes in the EVM
- Your code should have built-in safety checks for swap, mint, and burn. **You should not assume people will use a router but instead directly interface with your contract**
- The swap function should not support flash swaps, you should build a separate flashloan function that is compliant with ERC-3156
- Don’t use safemath with 0.8.0 or higher
- You should only implement the factory and the pair (which inherits from ERC20), don’t implement other contracts

- [ ]  Write a markdown file explaining how to use the TWAP oracle with Uniswap V2. Find it in the markdowns folder

- [ ]  Uniswap puzzles. Find it in `src/puzzles` folder. For this create a .env file with an alchemy mainnet url and run the following command:
```bash
source .env
forge test -f $<your-alchemy-mainnet-url>
```