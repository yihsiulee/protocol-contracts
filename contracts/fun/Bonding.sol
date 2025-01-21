// SPDX-License-Identifier: MIT
// Modified from https://github.com/sourlodine/Pump.fun-Smart-Contract/blob/main/contracts/PumpFun.sol
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./FFactory.sol";
import "./IFPair.sol";
import "./FRouter.sol";
import "./FERC20.sol";
import "../virtualPersona/IAgentFactoryV3.sol";

contract Bonding is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    address private _feeTo;

    FFactory public factory; //0x158d7CcaA23DC3c8861c3323eD546E3d25e74309
    FRouter public router; //0x8292B43aB73EfAC11FAF357419C38ACF448202C5
    uint256 public initialSupply; //1000000000
    uint256 public fee; // 100 ether (virtual)
    uint256 public constant K = 3_000_000_000_000;
    uint256 public assetRate; // 5000
    uint256 public gradThreshold; // 125000000 ether
    uint256 public maxTx; // 100
    address public agentFactory; // 0x71B8EFC8BCaD65a5D9386D07f2Dff57ab4EAf533
    struct Profile {
        address user;
        address[] tokens;
    }

    struct Token {
        address creator;
        address token;
        address pair;
        address agentToken;
        Data data;
        string description;
        uint8[] cores;
        string image;
        string twitter;
        string telegram;
        string youtube;
        string website;
        bool trading;
        bool tradingOnUniswap;
    }

    struct Data {
        address token;
        string name;
        string _name;
        string ticker;
        uint256 supply;
        uint256 price;
        uint256 marketCap;
        uint256 liquidity;
        uint256 volume;
        uint256 volume24H;
        uint256 prevPrice;
        uint256 lastUpdated;
    }

    struct DeployParams {
        bytes32 tbaSalt;
        address tbaImplementation;
        uint32 daoVotingPeriod;
        uint256 daoThreshold;
    }

    DeployParams private _deployParams;

    mapping(address => Profile) public profile;
    address[] public profiles;

    mapping(address => Token) public tokenInfo;
    address[] public tokenInfos;

    event Launched(address indexed token, address indexed pair, uint);
    event Deployed(address indexed token, uint256 amount0, uint256 amount1);
    event Graduated(address indexed token, address agentToken);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address factory_,
        address router_,
        address feeTo_,
        uint256 fee_,
        uint256 initialSupply_,
        uint256 assetRate_,
        uint256 maxTx_,
        address agentFactory_,
        uint256 gradThreshold_
    ) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        factory = FFactory(factory_);
        router = FRouter(router_);

        _feeTo = feeTo_;
        fee = (fee_ * 1 ether) / 1000;

        initialSupply = initialSupply_;
        assetRate = assetRate_;
        maxTx = maxTx_;

        agentFactory = agentFactory_;
        gradThreshold = gradThreshold_;
    }

    // for indexing the user to tokens
    function _createUserProfile(address _user) internal returns (bool) {
        address[] memory _tokens;

        Profile memory _profile = Profile({user: _user, tokens: _tokens});

        profile[_user] = _profile;

        profiles.push(_user);

        return true;
    }

    // for indexing the user to tokens
    function _checkIfProfileExists(address _user) internal view returns (bool) {
        return profile[_user].user == _user;
    }

    function _approval(
        address _spender,
        address _token,
        uint256 amount
    ) internal returns (bool) {
        IERC20(_token).forceApprove(_spender, amount);

        return true;
    }

    function setInitialSupply(uint256 newSupply) public onlyOwner {
        initialSupply = newSupply;
    }

    // 銷售門檻 達標要轉移至DEX
    function setGradThreshold(uint256 newThreshold) public onlyOwner {
        gradThreshold = newThreshold;
    }

    // 發行費用 以及to address
    function setFee(uint256 newFee, address newFeeTo) public onlyOwner {
        fee = newFee;
        _feeTo = newFeeTo;
    }

    // 設定每筆轉帳最大值
    function setMaxTx(uint256 maxTx_) public onlyOwner {
        maxTx = maxTx_;
    }

    // selling curve rate
    function setAssetRate(uint256 newRate) public onlyOwner {
        require(newRate > 0, "Rate err");

        assetRate = newRate;
    }

    function setDeployParams(DeployParams memory params) public onlyOwner {
        _deployParams = params;
    }

    function getUserTokens(
        address account
    ) public view returns (address[] memory) {
        require(_checkIfProfileExists(account), "User Profile dose not exist.");

        Profile memory _profile = profile[account];

        return _profile.tokens;
    }

    function launch(
        string memory _name,
        string memory _ticker,
        uint8[] memory cores, // ???
        string memory desc, // description
        string memory img,
        string[4] memory urls,
        uint256 purchaseAmount
    ) public nonReentrant returns (address, address, uint) {
        require(
            // fee = 100 virtuals
            purchaseAmount > fee,
            "Purchase amount must be greater than fee"
        );
        // VIRTUAL
        address assetToken = router.assetToken();
        require(
            // 檢查是否有足夠的VIRTUAL資產
            IERC20(assetToken).balanceOf(msg.sender) >= purchaseAmount,
            "Insufficient amount"
        );

        // 扣掉手續費的購買金額
        uint256 initialPurchase = (purchaseAmount - fee);
        IERC20(assetToken).safeTransferFrom(msg.sender, _feeTo, fee);
        IERC20(assetToken).safeTransferFrom(
            msg.sender,
            address(this),
            initialPurchase
        );

        // 建立內盤token
        FERC20 token = new FERC20(
            string.concat("fun ", _name),
            _ticker,
            initialSupply,
            maxTx // 轉帳最大值
        );
        uint256 supply = token.totalSupply();

        // 透過factory 建立FPair
        address _pair = factory.createPair(address(token), assetToken);

        // 給router approve
        bool approved = _approval(address(router), address(token), supply);
        require(approved);

        // 計算後 liquidity = 6000 ether (virtual)
        uint256 k = ((K * 10000) / assetRate);
        uint256 liquidity = (((k * 10000 ether) / supply) * 1 ether) / 10000;

        // 透過router 建立初始流動性 totalSupply = 1000000000
        router.addInitialLiquidity(address(token), supply, liquidity);

        Data memory _data = Data({
            token: address(token),
            name: string.concat("fun ", _name),
            _name: _name,
            ticker: _ticker,
            supply: supply,
            price: supply / liquidity,
            marketCap: liquidity,
            liquidity: liquidity * 2,
            volume: 0,
            volume24H: 0,
            prevPrice: supply / liquidity,
            lastUpdated: block.timestamp
        });
        Token memory tmpToken = Token({
            creator: msg.sender,
            token: address(token),
            agentToken: address(0),
            pair: _pair,
            data: _data,
            description: desc,
            cores: cores,
            image: img,
            twitter: urls[0],
            telegram: urls[1],
            youtube: urls[2],
            website: urls[3],
            trading: true, // Can only be traded once creator made initial purchase
            tradingOnUniswap: false
        });
        tokenInfo[address(token)] = tmpToken;
        tokenInfos.push(address(token));

        bool exists = _checkIfProfileExists(msg.sender);

        if (exists) {
            Profile storage _profile = profile[msg.sender];

            _profile.tokens.push(address(token));
        } else {
            bool created = _createUserProfile(msg.sender);

            if (created) {
                Profile storage _profile = profile[msg.sender];

                _profile.tokens.push(address(token));
            }
        }

        uint n = tokenInfos.length;

        emit Launched(address(token), _pair, n);

        // Make initial purchase
        IERC20(assetToken).forceApprove(address(router), initialPurchase);
        router.buy(initialPurchase, address(token), address(this));
        token.transfer(msg.sender, token.balanceOf(address(this)));

        return (address(token), _pair, n);
    }

    function sell(
        uint256 amountIn,
        address tokenAddress
    ) public returns (bool) {
        require(tokenInfo[tokenAddress].trading, "Token not trading");

        address pairAddress = factory.getPair(
            tokenAddress,
            router.assetToken()
        );

        IFPair pair = IFPair(pairAddress);

        (uint256 reserveA, uint256 reserveB) = pair.getReserves();

        (uint256 amount0In, uint256 amount1Out) = router.sell(
            amountIn,
            tokenAddress,
            msg.sender
        );

        uint256 newReserveA = reserveA + amount0In;
        uint256 newReserveB = reserveB - amount1Out;
        uint256 duration = block.timestamp -
            tokenInfo[tokenAddress].data.lastUpdated;

        uint256 liquidity = newReserveB * 2;
        uint256 mCap = (tokenInfo[tokenAddress].data.supply * newReserveB) /
            newReserveA;
        uint256 price = newReserveA / newReserveB;
        uint256 volume = duration > 86400
            ? amount1Out
            : tokenInfo[tokenAddress].data.volume24H + amount1Out;
        uint256 prevPrice = duration > 86400
            ? tokenInfo[tokenAddress].data.price
            : tokenInfo[tokenAddress].data.prevPrice;

        tokenInfo[tokenAddress].data.price = price;
        tokenInfo[tokenAddress].data.marketCap = mCap;
        tokenInfo[tokenAddress].data.liquidity = liquidity;
        tokenInfo[tokenAddress].data.volume =
            tokenInfo[tokenAddress].data.volume +
            amount1Out;
        tokenInfo[tokenAddress].data.volume24H = volume;
        tokenInfo[tokenAddress].data.prevPrice = prevPrice;

        if (duration > 86400) {
            tokenInfo[tokenAddress].data.lastUpdated = block.timestamp;
        }

        return true;
    }

    // 只能在內盤買
    function buy(
        uint256 amountIn, // VIRTUAL IN
        address tokenAddress
    ) public payable returns (bool) {
        // 如果是initial sale, 會是true
        // 如果是dex sale，會是false
        require(tokenInfo[tokenAddress].trading, "Token not trading");

        address pairAddress = factory.getPair(
            tokenAddress,
            router.assetToken()
        );

        IFPair pair = IFPair(pairAddress);
        // A 是 MEME，B 是 VIRTUAL
        // 取得剩餘數量
        (uint256 reserveA, uint256 reserveB) = pair.getReserves();

        // 計算輸入輸量以及可獲得的輸量
        // amountIn & amount1In 差異為扣除手續費
        (uint256 amount1In, uint256 amount0Out) = router.buy(
            amountIn,
            tokenAddress,
            msg.sender
        );

        uint256 newReserveA = reserveA - amount0Out;
        uint256 newReserveB = reserveB + amount1In;
        uint256 duration = block.timestamp -
            tokenInfo[tokenAddress].data.lastUpdated;

        uint256 liquidity = newReserveB * 2;
        uint256 mCap = (tokenInfo[tokenAddress].data.supply * newReserveB) /
            newReserveA;
        uint256 price = newReserveA / newReserveB;
        uint256 volume = duration > 86400
            ? amount1In
            : tokenInfo[tokenAddress].data.volume24H + amount1In;
        uint256 _price = duration > 86400
            ? tokenInfo[tokenAddress].data.price
            : tokenInfo[tokenAddress].data.prevPrice;

        tokenInfo[tokenAddress].data.price = price;
        tokenInfo[tokenAddress].data.marketCap = mCap;
        tokenInfo[tokenAddress].data.liquidity = liquidity;
        tokenInfo[tokenAddress].data.volume =
            tokenInfo[tokenAddress].data.volume +
            amount1In;
        tokenInfo[tokenAddress].data.volume24H = volume;
        tokenInfo[tokenAddress].data.prevPrice = _price;

        if (duration > 86400) {
            tokenInfo[tokenAddress].data.lastUpdated = block.timestamp;
        }

        // gradThreshold = 0.125 B ether
        if (newReserveA <= gradThreshold && tokenInfo[tokenAddress].trading) {
            // 交易達到特定數字 開新dex
            _openTradingOnUniswap(tokenAddress);
        }

        return true;
    }

    // TODO: 把uniswap改成gamedex
    function _openTradingOnUniswap(address tokenAddress) private {
        FERC20 token_ = FERC20(tokenAddress);

        Token storage _token = tokenInfo[tokenAddress];

        require(
            _token.trading && !_token.tradingOnUniswap,
            "trading is already open"
        );

        _token.trading = false;
        _token.tradingOnUniswap = true;

        // Transfer asset tokens to bonding contract
        address pairAddress = factory.getPair(
            tokenAddress,
            router.assetToken()
        );

        IFPair pair = IFPair(pairAddress);

        uint256 assetBalance = pair.assetBalance();
        uint256 tokenBalance = pair.balance();
        // 轉移 assetBalance(virtual) 給 this bonding contract (原本token 在 pair contract)
        router.graduate(tokenAddress);

        // approve agentFactory 轉移 assetBalance
        IERC20(router.assetToken()).forceApprove(agentFactory, assetBalance);

        // 將init sale中所有的VIRTUAL 轉移給 agentFactory
        uint256 id = IAgentFactoryV3(agentFactory).initFromBondingCurve(
            string.concat(_token.data._name, " by Virtuals"),
            _token.data.ticker,
            _token.cores,
            _deployParams.tbaSalt,
            _deployParams.tbaImplementation,
            _deployParams.daoVotingPeriod,
            _deployParams.daoThreshold,
            assetBalance
        );

        // 建立DEX上的token 以及一些流動性邏輯
        address agentToken = IAgentFactoryV3(agentFactory)
            .executeBondingCurveApplication(
                id,
                // 1B ether MEME tokens
                _token.data.supply / (10 ** token_.decimals()),
                // 剩餘的MEME tokens
                tokenBalance / (10 ** token_.decimals()),
                pairAddress
            );
        _token.agentToken = agentToken;

        // FRouter
        router.approval(
            pairAddress, // pair
            agentToken, // asset
            address(this), // spender
            IERC20(agentToken).balanceOf(pairAddress) // amount
        );

        token_.burnFrom(pairAddress, tokenBalance);

        emit Graduated(tokenAddress, agentToken);
    }

    // 1:1 兌換token
    function unwrapToken(
        address srcTokenAddress,
        address[] memory accounts
    ) public {
        Token memory info = tokenInfo[srcTokenAddress];
        require(info.tradingOnUniswap, "Token is not graduated yet");

        FERC20 token = FERC20(srcTokenAddress);
        IERC20 agentToken = IERC20(info.agentToken);
        address pairAddress = factory.getPair(
            srcTokenAddress,
            router.assetToken()
        );
        for (uint i = 0; i < accounts.length; i++) {
            address acc = accounts[i];
            uint256 balance = token.balanceOf(acc);
            if (balance > 0) {
                token.burnFrom(acc, balance);
                agentToken.transferFrom(pairAddress, acc, balance);
            }
        }
    }
}
