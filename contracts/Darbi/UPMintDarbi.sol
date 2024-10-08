// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../UP.sol";
import "../UPController.sol";
import "../Helpers/Safe.sol";

/// @title UP Darbi Mint
/// @author Daniel Blanco & A Fistful of Stray Cat Hair
/// @notice This contract allows to DARBi to mint UP at virtual price.

contract UPMintDarbi is AccessControl, Pausable, Safe {
  bytes32 public constant DARBI_ROLE = keccak256("DARBI_ROLE");

  address payable public UP_TOKEN = payable(address(0));
  address payable public UP_CONTROLLER = payable(address(0));

  modifier onlyDarbi() {
    require(hasRole(DARBI_ROLE, msg.sender), "UPMintDarbi: ONLY_DARBI");
    _;
  }

  modifier onlyAdmin() {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "UPMintDarbi: ONLY_ADMIN");
    _;
  }

  event DarbiMint(address indexed _from, uint256 _amount, uint256 _price, uint256 _value);
  event UpdateController(address _upController);

  constructor(
    address _UP,
    address _UPController,
    address _fundsTarget
  ) Safe(_fundsTarget) {
    require(_UP != address(0), "UPMintDarbi: Invalid UP address");
    UP_TOKEN = payable(_UP);
    UP_CONTROLLER = payable(_UPController);
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  /// @notice Payable function that mints UP at the mint rate, deposits the native tokens to the UP Controller, Sends UP to the Msg.sender
  function mintUP() public payable whenNotPaused onlyDarbi {
    require(msg.value > 0, "UPMintDarbi: INVALID_PAYABLE_AMOUNT");
    uint256 currentPrice = UPController(UP_CONTROLLER).getVirtualPrice();
    if (currentPrice == 0) return;
    uint256 mintAmount = (msg.value * 1e18) / currentPrice;
    UP(UP_TOKEN).mint(msg.sender, mintAmount);
    (bool successTransfer, ) = UP_CONTROLLER.call{value: msg.value}(""); /// GO BACK
    require(successTransfer, "UPMintDarbi: FAIL_SENDING_NATIVE");
    emit DarbiMint(msg.sender, mintAmount, currentPrice, msg.value);
  }

  ///@notice Permissioned function to update the address of the UP Controller
  ///@param _upController - the address of the new UP Controller
  function updateController(address _upController) public onlyAdmin {
    require(_upController != address(0), "UPMintDarbi: INVALID_ADDRESS");
    UP_CONTROLLER = payable(_upController);
    emit UpdateController(_upController);
  }

  ///@notice Grant DARBi role
  ///@param _darbiAddr - a new DARBi address
  function grantDarbiRole(address _darbiAddr) public onlyAdmin {
    require(_darbiAddr != address(0), "UPMintDarbi: INVALID_ADDRESS");
    grantRole(DARBI_ROLE, _darbiAddr);
  }

  ///@notice Revoke DARBi role
  ///@param _darbiAddr - DARBi address to revoke
  function revokeDarbiRole(address _darbiAddr) public onlyAdmin {
    require(_darbiAddr != address(0), "UPMintDarbi: INVALID_ADDRESS");
    revokeRole(DARBI_ROLE, _darbiAddr);
  }

  ///@notice Permissioned function to withdraw any native coins accidentally deposited to the Darbi Mint contract.
  function withdrawFunds() public onlyAdmin returns (bool) {
    return _withdrawFunds();
  }

  ///@notice Permissioned function to withdraw any tokens accidentally deposited to the Darbi Mint contract.
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

  fallback() external payable {}

  receive() external payable {}
}
