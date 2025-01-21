
There are two sales, one is the initial sale, and the other is the DEX sale.
Note: virtual using 2 different tokens for the two sales. 1:1 ratio to exchange.


## insdie (init sale)

- FERC20: MEME Token in the initial sale
- Bonding: is used for the bonding curve sale.
  - sell 
  - buy
  - launch: _openTradingOnUniswap()
  - unwrapToken: change inside token to outside token
- FFactory
- FPair
- FRouter

## outside (DEX)

- another token in the DEX sale: 1:1 ratio to exchange with MEME Token
- AgentFactoryV3: factory to create and store the outside token
- AgentToken: the outside token contract



### Contract

Bonding.sol Functions:


initialize()
- set the init params when the contract is initialized


_createUserProfile()
_checkIfProfileExists()
- for indexing the user to tokens

launch()

set up token infos
```solidity
string memory _name,
string memory _ticker,
uint8[] memory cores, // ???
string memory desc, // description
string memory img,
string[4] memory urls,
uint256 purchaseAmount
```

createPair through the FFactory.sol
```solidity
address _pair = factory.createPair(address(token), assetToken);
```

createPair() in the FFactory.sol
```solidity
    function _createPair(
        address tokenA,
        address tokenB
    ) internal returns (address) {
        require(tokenA != address(0), "Zero addresses are not allowed.");
        require(tokenB != address(0), "Zero addresses are not allowed.");
        require(router != address(0), "No router");

/// recording the pair token
/// token A is the MEME token
/// token B is the VIRTUAL token
        FPair pair_ = new FPair(router, tokenA, tokenB);

        _pair[tokenA][tokenB] = address(pair_);
        _pair[tokenB][tokenA] = address(pair_);

        pairs.push(address(pair_));

        uint n = pairs.length;

        emit PairCreated(tokenA, tokenB, address(pair_), n);

        return address(pair_);
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external onlyRole(CREATOR_ROLE) nonReentrant returns (address) {
        address pair = _createPair(tokenA, tokenB);

        return pair;
    }
```


addInitialLiquidity() in Bonding.sol
- add liquidity to the pair
```solidity
router.addInitialLiquidity(address(token), supply, liquidity);
```

addInitialLiquidity() in FRouter.sol
```solidity
    function addInitialLiquidity(
        address token_,
        uint256 amountToken_,
        uint256 amountAsset_
    ) public onlyRole(EXECUTOR_ROLE) returns (uint256, uint256) {
        require(token_ != address(0), "Zero addresses are not allowed.");

        address pairAddress = factory.getPair(token_, assetToken);

        IFPair pair = IFPair(pairAddress);

        IERC20 token = IERC20(token_);

        token.safeTransferFrom(msg.sender, pairAddress, amountToken_);

        pair.mint(amountToken_, amountAsset_);

        return (amountToken_, amountAsset_);
    }
```

buy() in Bonding.sol
```solidity
// gradThreshold = 0.125 B ether
        if (newReserveA <= gradThreshold && tokenInfo[tokenAddress].trading) {
            // create DEX
            _openTradingOnUniswap(tokenAddress);
        }
```

_openTradingOnUniswap() in Bonding.sol  
- to open trading on the DEX


This for transferring virtual token to bonding contract
```solidity
router.graduate(tokenAddress);
```

graduate() in FRouter.sol
```solidity
function graduate(
        address tokenAddress
    ) public onlyRole(EXECUTOR_ROLE) nonReentrant {
        require(tokenAddress != address(0), "Zero addresses are not allowed.");
        address pair = factory.getPair(tokenAddress, assetToken);
        uint256 assetBalance = IFPair(pair).assetBalance();
        FPair(pair).transferAsset(msg.sender, assetBalance);
    }
```