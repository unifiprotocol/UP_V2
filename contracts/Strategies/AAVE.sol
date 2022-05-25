// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Strategy.sol";
import "./Interfaces/ILendingPool.sol";
import "./Interfaces/IWETHGateway.sol";
import "./Interfaces/IAaveIncentivesController.sol";
import "../Helpers/Safe.sol";


/// @title Staking Contract for UP to interact with AAVE
/// @author dxffffff & A Fistful of Stray Cat Hair
/// @notice This controller deposits the native tokens backing UP into the AAVE Supply Pool, and triggers the Rebalancer

contract AAVE is AccessControl, Safe {
  bytes32 public constant INVOKER_ROLE = keccak256("INVOKER_ROLE");
  bytes32 public constant REBALANCER_ROLE = keccak256("INVOKER_ROLE");
  address public rebalancer = address(0);
  address public invoker = address(0);
  uint256 public amountDeposited = 0;
  address public wrappedTokenAddress = 0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a; //WONE Address
  address public aaveIncentivesController = 0x929EC64c34a17401F460460D4B9390518E5B473e; //AAVE Harmony Incentives Controller
  address public aavePool = 0x794a61358D6845594F94dc1DB02A252b5b4814aD; //AAVE Harmony Lending Pool
  address public wethGateway = 0xe86B52cE2e4068AdE71510352807597408998a69; //AAVE Harmony WETH Gateway
  address public aaveDepositToken = 0x6d80113e533a2C0fe82EaBD35f1875DcEA89Ea97; /// AAVE WONE AToken

  modifier onlyAdmin() {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ONLY_ADMIN");
    _;
  }

  modifier onlyInvoker() {
    require(hasRole(INVOKER_ROLE, msg.sender), "ONLY_INVOKER");
    _;
  }

  modifier onlyRebalancer() {
    require(hasRole(REBALANCER_ROLE, msg.sender), "ONLY_REBALANCER");
    _;
  }

  event amountEarned(uint256 earnings);
  event UpdateRebalancer(address _rebalancer);
  event UpdateInvoker(address _invoker);

  constructor(address _rebalancer, address _invoker, address _wrappedTokenAddress, address _aaveIncentivesController, address _aavePool, address _wethGateway, address _aaveDepositToken) {
    rebalancer = _rebalancer;
    invoker = _invoker;
    wrappedTokenAddress = _wrappedTokenAddress;
    aaveIncentivesController = _aaveIncentivesController;
    aavePool = _aavePool;
    wethGateway = _wethGateway;
    aaveDepositToken = _aaveDepositToken;
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(INVOKER_ROLE, msg.sender);
    _setupRole(REBALANCER_ROLE, msg.sender);
  }

  /// Read Functions

  ///@notice Checks the total amount of rewards earned by this address.
  function checkRewardsBalance() public view returns (uint256 rewardsBalance) {
    address[] memory asset = new address[](1);
    asset[0] = address(wrappedTokenAddress);
    rewardsBalance = IAaveIncentivesController(aaveIncentivesController).getUserRewards(asset, address(this), wrappedTokenAddress);
    return (rewardsBalance);
  }

  ///@notice Alternative? 
  // function checkUnclaimedRewards() public returns (uint256 unclaimedRewards) {
  //   unclaimedRewards = IAaveIncentivesController(aaveIncentivesController).getUserUnclaimedRewards(address(this));
  //   return (unclaimedRewards);
  // }

  ///@notice Checks amonut of assets to AAVe by this address.
  function checkAAVEBalance() public view returns (uint256 aaveBalance) {
    (uint256 aaveBalanceData,,,,,) = ILendingPool(aavePool).getUserAccountData(address(this));
    aaveBalance = aaveBalanceData;
    return (aaveBalance);
  }

  ///@notice Checks Total Amount Earned by AAVE deposit above deposited total.
  function checkUnclaimedEarnings() public view returns (uint256 unclaimedEarnings) {
    (uint256 aaveBalance) = checkAAVEBalance();
    uint256 aaveEarnings = aaveBalance - amountDeposited;
    (uint256 rewardsBalance) = checkRewardsBalance();
    unclaimedEarnings = aaveEarnings + rewardsBalance;
    return (unclaimedEarnings);
  }

  /// Write Functions

  ///@notice Claims AAVE Incentive Rewards earned by this address.
  function _claimAAVERewards() internal returns (uint256 rewardsClaimed) {
    address[] memory asset = new address[](1);
    asset[0] = address(wrappedTokenAddress);
    uint256 rewardsBalance = IAaveIncentivesController(aaveIncentivesController).getUserRewards(asset, address(this), wrappedTokenAddress);
    rewardsClaimed = IAaveIncentivesController(aaveIncentivesController).claimRewards(asset, rewardsBalance, address(this), wrappedTokenAddress);
    return (rewardsBalance);
  }

  ///@notice Withdraws All Native Token Deposits from AAVE. 
  function _withdrawAAVE() internal {
    (uint256 aaveBalance) = checkAAVEBalance();
    uint256 lpBalance = IERC20(aaveDepositToken).balanceOf(address(this));
    IERC20(aaveDepositToken).approve(wethGateway, lpBalance);
    IWETHGateway(wethGateway).withdrawETH(aavePool, aaveBalance, address(this));
    amountDeposited = 0;
  }

   ///@notice Deposits native tokens to AAVE.
  function depositAAVE() public payable onlyRebalancer {
    uint256 depositValue = msg.value;
    IWETHGateway(wethGateway).depositETH{value: depositValue}(aavePool, address(this), 0);
    amountDeposited = depositValue;
  }

  ///@notice Claims Rewards + Withdraws All Tokens on AAVE, and sends to Controller
  function gather() public onlyInvoker {
    uint256 earnings = checkUnclaimedEarnings();
    _claimAAVERewards();
    _withdrawAAVE();
    (bool successTransfer, ) = address(rebalancer).call{value: address(this).balance}("");
    emit amountEarned(earnings);
  }
  
  ///Admin Functions
  
  ///@notice Permissioned function to update the address of the Rebalancer
  ///@param _rebalancer - the address of the new rebalancer
  function updateRebalancer(address _rebalancer) public onlyAdmin {
    require(_rebalancer != address(0), "INVALID_ADDRESS");
    rebalancer = _rebalancer;
    emit UpdateRebalancer(_rebalancer);
  }

  ///@notice Permissioned function to update the address of the Invoker
  ///@param _invoker - the address of the new rebalancer
  function updateInvoker(address _invoker) public onlyAdmin {
    require(_invoker != address(0), "INVALID_ADDRESS");
    invoker = _invoker;
    emit UpdateInvoker(_invoker);
  }

  ///@notice Permissioned function to update the address of the Aave Incentives Controller
  ///@param _aaveIncentivesController - the address of the new Aave Incentives Controller
  function updateaaveIncentivesController(address _aaveIncentivesController) public onlyAdmin {
    require(_aaveIncentivesController != address(0), "INVALID_ADDRESS");
    aaveIncentivesController = _aaveIncentivesController;
  }

  ///@notice Permissioned function to update the address of the aavePool
  ///@param _aavePool - the address of the new aavePool
  function updateaavePool(address _aavePool) public onlyAdmin {
    require(_aavePool != address(0), "INVALID_ADDRESS");
    aavePool = _aavePool;
  }

  ///@notice Permissioned function to update the address of the wethGateway
  ///@param _wethGateway - the address of the new wethGateway
  function updatewethGateway(address _wethGateway) public onlyAdmin {
    require(_wethGateway != address(0), "INVALID_ADDRESS");
    wethGateway = _wethGateway;
  }

  ///@notice Permissioned function to update the address of the aaveDepositToken
  ///@param _aaveDepositToken - the address of the new aaveDepositToken
  function updateaaveDepositToken(address _aaveDepositToken) public onlyAdmin {
    require(_aaveDepositToken != address(0), "INVALID_ADDRESS");
    aaveDepositToken = _aaveDepositToken;
  }
}
