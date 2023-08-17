// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/*@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
     @@@@@  HYPERLANE  @@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
@@@@@@@@@       @@@@@@@@*/

// ============ Internal Imports ============
import {Message} from "../libs/Message.sol";
import {IPostDispatchHook} from "../interfaces/hooks/IPostDispatchHook.sol";
// ============ External Imports ============
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StaticProtocolFee
 * @notice Collects a static protocol fee from the sender.
 * @dev V3 WIP
 */
contract StaticProtocolFee is IPostDispatchHook, Ownable {
    using Address for address payable;
    using Message for bytes;

    // ============ Constants ============

    /// @notice The maximum protocol fee that can be set.
    uint256 public immutable MAX_PROTOCOL_FEE;

    // ============ Public Storage ============

    /// @notice The current protocol fee.
    uint256 public protocolFee;
    /// @notice The beneficiary of protocol fees.
    address public beneficiary;

    // ============ Constructor ============

    constructor(
        uint256 _maxProtocolFee,
        uint256 _protocolFee,
        address _beneficiary,
        address _owner
    ) {
        MAX_PROTOCOL_FEE = _maxProtocolFee;
        _setProtocolFee(_protocolFee);
        _setBeneficiary(_beneficiary);
        _transferOwnership(_owner);
    }

    // ============ External Functions ============

    /**
     * @notice Collects the protocol fee from the sender.
     */
    function postDispatch(bytes calldata, bytes calldata message)
        external
        payable
        override
    {
        require(
            msg.value >= protocolFee,
            "StaticProtocolFee: insufficient protocol fee"
        );

        uint256 refund = msg.value - protocolFee;
        if (refund > 0) payable(message.senderAddress()).sendValue(refund);
    }

    /**
     * @notice Sets the protocol fee.
     * @param _protocolFee The new protocol fee.
     */
    function setProtocolFee(uint256 _protocolFee) external onlyOwner {
        _setProtocolFee(_protocolFee);
    }

    /**
     * @notice Sets the beneficiary of protocol fees.
     * @param _beneficiary The new beneficiary.
     */
    function setBeneficiary(address _beneficiary) external onlyOwner {
        _setBeneficiary(_beneficiary);
    }

    /**
     * @notice Collects protocol fees from the contract.
     */
    function collectProtocolFees() external {
        payable(beneficiary).sendValue(address(this).balance);
    }

    // ============ Internal Functions ============

    /**
     * @notice Sets the protocol fee.
     * @param _protocolFee The new protocol fee.
     */
    function _setProtocolFee(uint256 _protocolFee) internal {
        require(
            _protocolFee <= MAX_PROTOCOL_FEE,
            "StaticProtocolFee: exceeds max protocol fee"
        );
        protocolFee = _protocolFee;
    }

    /**
     * @notice Sets the beneficiary of protocol fees.
     * @param _beneficiary The new beneficiary.
     */
    function _setBeneficiary(address _beneficiary) internal {
        require(
            _beneficiary != address(0),
            "StaticProtocolFee: invalid beneficiary"
        );
        beneficiary = _beneficiary;
    }
}