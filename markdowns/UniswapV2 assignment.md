- Why does the `price0CumulativeLast` and `price1CumulativeLast` never decrement?
   Both of them increase every time `_update()` is called until they overflow. The same name can give us a hint for this as it is called "cumulative". It is a cumulative value that is never decremented.
  
- How do you write a contract that uses the oracle?
  We need to anticipate the moment we need to check the `price0CumulativeLast` variable and the function `getReserves()` and snapshot the prices at the moment we need, but if there is no interaction in the pool we might be fetching prices pretty old. To fix this we call the function `sync()` at the moment we need to get the price.
  
- Why are `price0CumulativeLast` and `price1CumulativeLast` stored separately? Why not just calculate ``price1CumulativeLast = 1/price0CumulativeLast`?
As both of them store accumulated prices since the pool is launched, performing a division like this one will easily give as result an innacurate value.