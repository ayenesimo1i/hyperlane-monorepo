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

/**
 * Format of metadata:
 *
 * [0:32] Gas limit for message
 * [32:52] Refund address for message
 */
library IGPMetadata {
    uint8 private constant GAS_LIMIT_OFFSET = 0;
    uint8 private constant REFUND_ADDRESS_OFFSET = 32;

    /**
     * @notice Returns the specified gas limit for the message.
     * @param _metadata ABI encoded IGP hook metadata.
     * @return Gas limit for the message as uint256.
     */
    function gasLimit(bytes calldata _metadata)
        internal
        pure
        returns (uint256)
    {
        return
            uint256(bytes32(_metadata[GAS_LIMIT_OFFSET:GAS_LIMIT_OFFSET + 32]));
    }

    /**
     * @notice Returns the specified refund address for the message.
     * @param _metadata ABI encoded IGP hook metadata.
     * @return Refund address for the message as address.
     */
    function refundAddress(bytes calldata _metadata)
        internal
        pure
        returns (address)
    {
        return
            address(
                bytes20(
                    _metadata[REFUND_ADDRESS_OFFSET:REFUND_ADDRESS_OFFSET + 20]
                )
            );
    }

    /**
     * @notice Formats the specified gas limit and refund address into IGP hook metadata.
     * @param _gasLimit Gas limit for the message.
     * @param _refundAddress Refund address for the message.
     * @return ABI encoded IGP hook metadata.
     */
    function formatMetadata(uint256 _gasLimit, address _refundAddress)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(bytes32(_gasLimit), bytes20(_refundAddress));
    }
}