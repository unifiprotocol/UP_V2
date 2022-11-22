// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../Libraries/UniswapHelper.sol";
import "../Helpers/Safe.sol";
import "../UPController.sol";
import "./UPMintDarbi.sol";
import "../Rebalancer.sol";

contract Darbi is AccessControl, Pausable, Safe {
  using SafeERC20 for IERC20;

  bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");
  bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

  address public factory;
  address public WETH;
  address public rebalancer;
  address public gasRefundAddress;
  // address public strategy; Not necessary to make variable in Darbi, as strategy address is held in Rebalancer. Makes upgrade easier.
  uint256 public arbitrageThreshold = 100000;
  uint256 public gasRefund = 3500000000000000;
  bool public fundingFromStrategy; // if True, Darbi funding comes from Strategy. If false, Darbi funding comes from Controller.
  // Add Function to Change Value
  bool public strategyLockup; // if True, funds in Strategy are cannot be withdrawn immediately (such as staking on Harmony). If false, funds in Strategy are always available (such as AAVE on Polygon).
  // Add Function to Change Value
  IERC20 public UP_TOKEN;
  IUniswapV2Router02 public router;
  UPController public UP_CONTROLLER;
  UPMintDarbi public DARBI_MINTER;

  event Arbitrage(bool isSellingUp, uint256 actualAmountIn);

  modifier onlyAdmin() {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Darbi: ONLY_ADMIN");
    _;
  }

  modifier onlyMonitor() {
    require(hasRole(MONITOR_ROLE, msg.sender), "Darbi: ONLY_MONITOR");
    _;
  }

  modifier onlyRebalancer() {
    require(hasRole(REBALANCER_ROLE, msg.sender), "Darbi: ONLY_REBALANCER");
    _;
  }

  modifier onlyRebalancerOrMonitor() {
    require(
      hasRole(REBALANCER_ROLE, msg.sender) || hasRole(MONITOR_ROLE, msg.sender),
      "Darbi: ONLY_REBALANCER_OR_MONITOR"
    );
    _;
  }

  constructor(
    address _factory,
    address _router,
    address _rebalancer,
    address _WETH,
    address _gasRefundAddress,
    address _UP_CONTROLLER,
    address _darbiMinter,
    address _fundsTarget
  ) Safe(_fundsTarget) {
    factory = _factory;
    router = IUniswapV2Router02(_router);
    rebalancer = _rebalancer;
    WETH = _WETH;
    gasRefundAddress = _gasRefundAddress;
    UP_CONTROLLER = UPController(payable(_UP_CONTROLLER));
    DARBI_MINTER = UPMintDarbi(payable(_darbiMinter));
    UP_TOKEN = IERC20(payable(UP_CONTROLLER.UP_TOKEN()));
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  receive() external payable {}

  function _checkAvailableFunds() internal view returns (uint256 fundsAvailable) {
    if (fundingFromStrategy == true) {
      address strategyAddress = Rebalancer(address(rebalancer)).strategy();
      if (strategyLockup == true) {
        fundsAvailable = address(strategyAddress).balance;
      } else {
        fundsAvailable = IStrategy(address(strategyAddress)).amountDeposited();
      }
    } else {
      fundsAvailable = (address(UP_CONTROLLER).balance / 3);
    }
    return fundsAvailable;
  }

  //   /// Notes - Could just save all this logic by having a stored variable with the address of the funding source, seems easier, both using borrowNative function (GOING TO DO THIS)
  //   /// 1) Check if Funding from Strategy
  //   /// 1a) If not funding from strategy, it is funding from controller. Available funds equal 20% of controller balance. This will allow Darbi to function in ALMOST ALL situations.
  //   /// 2) Check if Strategy Involves Lock Up
  //   /// 2a) If involves lock up, check balance of strategy wallet
  //   /// 2b) If does involve lock up, check total amount deposited.
  //   ///
  //   if (address strategy = IRebalancer(rebalancer).strategy(); // Checks Address of Strategy
  //   uint256 fundsAvailableInController = (address(UP_CONTROLLER).balance / 3); // Checks balance of UP Controller, divides by 3 as there must be enough balance for UP to be redeemed
  //   if (strategy != address(0)) {
  //     uint256 fundsAvailableInStrategy = address(strategy).balance; // Check balance of for Harmony, or any chain where assets CAN NOT be immediately accessed.
  //     // fundsAvailable = IStrategy(address(strategy)).amountDeposited(); // for Polygon, or any chain where assets CAN be immediately accessed.
  //     // fundsAvailable = IStrategy(address(strategy)).amountDeposited(); // for BSC
  //     if (fundsAvailableInController < fundsAvailableInStrategy) {
  //       fundsAvailable = fundsAvailableInStrategy;
  //       fundingSource = strategy;
  //     } else {
  //       fundsAvailable = fundsAvailableInController;
  //       fundingSource = UP_CONTROLLER;
  //     }
  //   } else {
  //     fundsAvailable = fundsAvailableInController;
  //     fundingSource = UP_CONTROLLER;
  //   }
  //   return (fundsAvailable, fundingSource);
  // }

  function _calculateArbitrage() internal whenNotPaused {}

  function arbitrage() public whenNotPaused {
    (
      bool aToB,
      uint256 amountIn,
      uint256 reserves0,
      uint256 reserves1,
      uint256 backedValue
    ) = moveMarketBuyAmount();

    // aToB == true == Buys UP
    // aToB == fals == Sells UP
    uint256 fundsAvailable = _checkAvailableFunds();
    uint256 actualAmountIn = (amountIn * 1000) / 997;
    uint256 tradeSize;
    // If Buying UP
    if (!aToB) {
      while (actualAmountIn > 0) {
        if (actualAmountIn > fundsAvailable) {
          tradeSize = fundsAvailable;
          actualAmountIn -= tradeSize;
        } else {
          tradeSize = actualAmountIn;
          actualAmountIn == 0;
        }
        if (fundingFromStrategy == true) {
          address strategyAddress = Rebalancer(address(rebalancer)).strategy();
          IStrategy(address(strategyAddress)).withdraw(tradeSize);
        } else {
          UPController.borrowNative(tradeSize, address(this));
        }
        _arbitrageBuy(tradeSize, amountIn, backedValue, reserves0, reserves1);
        if (fundingFromStrategy == true) {
          address strategyAddress = Rebalancer(address(rebalancer)).strategy();
          IStrategy(address(strategyAddress)).deposit(tradeSize);
        } else {
          UPController.repay{value: tradeSize}("");
        }
      }
    } else {
      while (actualAmountIn > 0) {
        if (actualAmountIn > fundsAvailable) {
          tradeSize = fundsAvailable;
          actualAmountIn -= tradeSize;
        } else {
          tradeSize = actualAmountIn;
          actualAmountIn == 0;
        }
        if (fundingFromStrategy == true) {
          address strategyAddress = Rebalancer(address(rebalancer)).strategy();
          IStrategy(address(strategyAddress)).withdraw(tradeSize);
        } else {
          UPController.borrowNative(tradeSize, address(this));
        }
        _arbitrageSell(tradeSize, amountIn, backedValue);
        if (fundingFromStrategy == true) {
          address strategyAddress = Rebalancer(address(rebalancer)).strategy();
          IStrategy(address(strategyAddress)).deposit(tradeSize);
        } else {
          UPController.repay{value: tradeSize}("");
        }
      }
    }
    _refund();
  }

  function forceArbitrage() public whenNotPaused onlyRebalancer {
    arbitrage();
  }

  function _arbitrageBuy(
    uint256 tradeSize,
    uint256 amountIn,
    uint256 backedValue,
    uint256 reservesUP,
    uint256 reservesETH
  ) internal {
    uint256 actualAmountIn = amountIn <= tradeSize ? amountIn : tradeSize; //Value is going to native
    uint256 expectedReturn = UniswapHelper.getAmountOut(actualAmountIn, reservesETH, reservesUP); // Amount of UP expected from Buy
    uint256 expectedNativeReturn = (expectedReturn * backedValue) / 1e18; //Amount of Native Tokens Expected to Receive from Redeem
    uint256 upControllerBalance = address(UP_CONTROLLER).balance;
    if (upControllerBalance < expectedNativeReturn) {
      uint256 upOutput = (upControllerBalance * 1e18) / backedValue; //Value in UP Token
      actualAmountIn = UniswapHelper.getAmountIn(upOutput, reservesETH, reservesUP); // Amount of UP expected from Buy
    }

    address[] memory path = new address[](2);
    path[0] = WETH;
    path[1] = address(UP_TOKEN);

    uint256[] memory amounts = router.swapExactETHForTokens{value: actualAmountIn}(
      0,
      path,
      address(this),
      block.timestamp + 150
    );

    UP_TOKEN.approve(address(UP_CONTROLLER), amounts[1]);
    UP_CONTROLLER.redeem(amounts[1]);

    emit Arbitrage(false, actualAmountIn);
  }

  function _arbitrageSell(
    uint256 tradeSize,
    uint256 amountIn,
    uint256 backedValue
  ) internal {
    // If selling UP
    uint256 darbiBalanceMaximumUpToMint = (tradeSize * 1e18) / backedValue; // Amount of UP that we can mint with current balances
    uint256 actualAmountIn = amountIn <= darbiBalanceMaximumUpToMint
      ? amountIn
      : darbiBalanceMaximumUpToMint; // Value in UP
    uint256 nativeToMint = (actualAmountIn * backedValue) / 1e18;
    DARBI_MINTER.mintUP{value: nativeToMint}();

    address[] memory path = new address[](2);
    path[0] = address(UP_TOKEN);
    path[1] = WETH;

    uint256 up2Balance = UP_TOKEN.balanceOf(address(this));
    UP_TOKEN.approve(address(router), up2Balance);
    router.swapExactTokensForETH(up2Balance, 0, path, address(this), block.timestamp + 150);

    emit Arbitrage(true, up2Balance);
  }

  function _refund() internal whenNotPaused {
    uint256 proceeds = address(this).balance;
    (bool success1, ) = (msg.sender).call{value: proceeds}("");
    require(success1, "Darbi: FAIL_SENDING_PROFITS_TO_CALLER");
  }

  function moveMarketBuyAmount()
    public
    view
    returns (
      bool aToB,
      uint256 amountIn,
      uint256 reservesUP,
      uint256 reservesETH,
      uint256 upPrice
    )
  {
    (reservesUP, reservesETH) = UniswapHelper.getReserves(
      factory,
      address(UP_TOKEN),
      address(WETH)
    );
    upPrice = UP_CONTROLLER.getVirtualPrice();

    (aToB, amountIn) = UniswapHelper.computeTradeToMoveMarket(
      1000000000000000000, // Ratio = 1:UPVirtualPrice
      upPrice,
      reservesUP,
      reservesETH
    );
    return (aToB, amountIn, reservesUP, reservesETH, upPrice);
  }

  function redeemUP() internal {
    UP_CONTROLLER.redeem(IERC20(UP_CONTROLLER.UP_TOKEN()).balanceOf(address(this)));
  }

  function setController(address _controller) public onlyAdmin {
    require(_controller != address(0));
    UP_CONTROLLER = UPController(payable(_controller));
  }

  function setArbitrageThreshold(uint256 _threshold) public onlyAdmin {
    require(_threshold > 0);
    arbitrageThreshold = _threshold;
  }

  function setGasRefund(uint256 _gasRefund) public onlyAdmin {
    require(_gasRefund > 0);
    gasRefund = _gasRefund;
  }

  function setGasRefundAddress(address _gasRefundAddress) public onlyAdmin {
    require(_gasRefundAddress != address(0));
    gasRefundAddress = _gasRefundAddress;
  }

  function setDarbiMinter(address _newMinter) public onlyAdmin {
    require(_newMinter != address(0));
    DARBI_MINTER = UPMintDarbi(payable(_newMinter));
  }

  function withdrawFunds() public onlyAdmin returns (bool) {
    return _withdrawFunds();
  }

  function withdrawFundsERC20(address tokenAddress) public onlyAdmin returns (bool) {
    return _withdrawFundsERC20(tokenAddress);
  }

  /// @notice Permissioned function to pause UPaddress Controller
  function pause() public onlyAdmin {
    _pause();
  }

  /// @notice Permissioned function to unpause UPaddress Controller
  function unpause() public onlyAdmin {
    _unpause();
  }
}
