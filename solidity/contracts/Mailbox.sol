// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

// ============ Internal Imports ============
import {Versioned} from "./upgrade/Versioned.sol";
import {Indexed} from "./Indexed.sol";
import {Message} from "./libs/Message.sol";
import {TypeCasts} from "./libs/TypeCasts.sol";
import {IInterchainSecurityModule, ISpecifiesInterchainSecurityModule} from "./interfaces/IInterchainSecurityModule.sol";
import {IPostDispatchHook} from "./interfaces/hooks/IPostDispatchHook.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {IMailbox} from "./interfaces/IMailbox.sol";

// ============ External Imports ============
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Mailbox is IMailbox, Indexed, Versioned, OwnableUpgradeable {
    // ============ Libraries ============

    using Message for bytes;
    using TypeCasts for bytes32;
    using TypeCasts for address;

    // ============ Constants ============

    // Domain of chain on which the contract is deployed
    uint32 public immutable localDomain;

    // ============ Public Storage ============

    // A monotonically increasing nonce for outbound unique message IDs.
    uint32 public nonce;

    // The latest dispatched message ID used for auth in post-dispatch hooks.
    bytes32 public latestDispatchedId;

    // The default ISM, used if the recipient fails to specify one.
    IInterchainSecurityModule public defaultIsm;

    // The default post dispatch hook, used for post processing of opting-in dispatches.
    IPostDispatchHook public defaultHook;

    // The required post dispatch hook, used for post processing of ALL dispatches.
    IPostDispatchHook public requiredHook;

    // Mapping of message ID to delivery context that processed the message.
    struct Delivery {
        // address sender;
        // uint48 gasUsed;
        uint48 timestamp;
        // IInterchainSecurityModule ism;
        // uint48 value?
    }
    mapping(bytes32 => Delivery) internal deliveries;

    // ============ Events ============

    /**
     * @notice Emitted when the default ISM is updated
     * @param module The new default ISM
     */
    event DefaultIsmSet(address indexed module);

    /**
     * @notice Emitted when the default hook is updated
     * @param hook The new default hook
     */
    event DefaultHookSet(address indexed hook);

    /**
     * @notice Emitted when the required hook is updated
     * @param hook The new required hook
     */
    event RequiredHookSet(address indexed hook);

    // ============ Constructor ============
    constructor(uint32 _localDomain) {
        localDomain = _localDomain;
    }

    // ============ Initializers ============
    function initialize(
        address _owner,
        address _defaultIsm,
        address _defaultHook,
        address _requiredHook
    ) external initializer {
        __Ownable_init();
        setDefaultIsm(_defaultIsm);
        setDefaultHook(_defaultHook);
        setRequiredHook(_requiredHook);
        transferOwnership(_owner);
    }

    // ============ External Functions ============
    /**
     * @notice Dispatches a message to the destination domain & recipient.
     * @param _destinationDomain Domain of destination chain
     * @param _recipientAddress Address of recipient on destination chain as bytes32
     * @param _messageBody Raw bytes content of message body
     * @return The message ID inserted into the Mailbox's merkle tree
     */
    function dispatch(
        uint32 _destinationDomain,
        bytes32 _recipientAddress,
        bytes calldata _messageBody
    ) external payable override returns (bytes32) {
        return
            dispatch(
                _destinationDomain,
                _recipientAddress,
                _messageBody,
                defaultHook,
                _messageBody[0:0]
            );
    }

    /**
     * @notice Dispatches a message to the destination domain & recipient.
     * @param destinationDomain Domain of destination chain
     * @param recipientAddress Address of recipient on destination chain as bytes32
     * @param messageBody Raw bytes content of message body
     * @param hookMetadata Metadata used by the post dispatch hook
     * @return The message ID inserted into the Mailbox's merkle tree
     */
    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata hookMetadata
    ) external payable override returns (bytes32) {
        return
            dispatch(
                destinationDomain,
                recipientAddress,
                messageBody,
                defaultHook,
                hookMetadata
            );
    }

    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        IPostDispatchHook hook,
        bytes calldata metadata
    ) public payable returns (bytes32) {
        /// CHECKS ///

        // Format the message into packed bytes.
        bytes memory message = Message.formatMessage(
            VERSION,
            nonce,
            localDomain,
            msg.sender.addressToBytes32(),
            destinationDomain,
            recipientAddress,
            messageBody
        );
        bytes32 id = message.id();

        /// EFFECTS ///

        nonce += 1;
        latestDispatchedId = id;
        emit Dispatch(msg.sender, destinationDomain, recipientAddress, message);
        emit DispatchId(id);

        /// INTERACTIONS ///
        uint256 requiredValue = requiredHook.quoteDispatch(metadata, message);
        requiredHook.postDispatch{value: requiredValue}(metadata, message);
        hook.postDispatch{value: msg.value - requiredValue}(metadata, message);

        return id;
    }

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external view returns (uint256 fee) {
        bytes memory message = Message.formatMessage(
            VERSION,
            nonce,
            localDomain,
            msg.sender.addressToBytes32(),
            destinationDomain,
            recipientAddress,
            messageBody
        );
        return
            requiredHook.quoteDispatch("", message) +
            defaultHook.quoteDispatch("", message);
    }

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata defaultHookMetadata
    ) external view returns (uint256 fee) {
        bytes memory message = Message.formatMessage(
            VERSION,
            nonce,
            localDomain,
            msg.sender.addressToBytes32(),
            destinationDomain,
            recipientAddress,
            messageBody
        );
        return
            requiredHook.quoteDispatch(defaultHookMetadata, message) +
            defaultHook.quoteDispatch(defaultHookMetadata, message);
    }

    function delivered(bytes32 _id) public view override returns (bool) {
        return deliveries[_id].timestamp > 0;
    }

    /**
     * @notice Attempts to deliver `_message` to its recipient. Verifies
     * `_message` via the recipient's ISM using the provided `_metadata`.
     * @param _metadata Metadata used by the ISM to verify `_message`.
     * @param _message Formatted Hyperlane message (refer to Message.sol).
     */
    function process(bytes calldata _metadata, bytes calldata _message)
        external
        payable
        override
    {
        /// CHECKS ///

        // Check that the message was intended for this mailbox.
        require(_message.version() == VERSION, "Mailbox: bad version");
        require(
            _message.destination() == localDomain,
            "Mailbox: unexpected destination"
        );

        // Check that the message hasn't already been delivered.
        bytes32 _id = _message.id();
        require(delivered(_id) == false, "Mailbox: already delivered");

        // Get the recipient's ISM.
        address recipient = _message.recipientAddress();
        IInterchainSecurityModule ism = recipientIsm(recipient);

        /// EFFECTS ///

        deliveries[_id] = Delivery({
            timestamp: uint48(block.timestamp)
            // sender: msg.sender
            // gasUsed: gasleft()
        });
        emit Process(_message.origin(), _message.sender(), recipient);
        emit ProcessId(_id);

        /// INTERACTIONS ///

        // Verify the message via the ISM.
        require(
            ism.verify(_metadata, _message),
            "Mailbox: verification failed"
        );

        // Deliver the message to the recipient.
        IMessageRecipient(recipient).handle{value: msg.value}(
            _message.origin(),
            _message.sender(),
            _message.body()
        );
    }

    // ============ Public Functions ============

    /**
     * @notice Sets the default ISM for the Mailbox.
     * @param _module The new default ISM. Must be a contract.
     */
    function setDefaultIsm(address _module) public onlyOwner {
        require(Address.isContract(_module), "Mailbox: !contract");
        defaultIsm = IInterchainSecurityModule(_module);
        emit DefaultIsmSet(_module);
    }

    /**
     * @notice Sets the default post dispatch hook for the Mailbox.
     * @param _hook The new default post dispatch hook. Must be a contract.
     */
    function setDefaultHook(address _hook) public onlyOwner {
        require(Address.isContract(_hook), "Mailbox: !contract");
        defaultHook = IPostDispatchHook(_hook);
        emit DefaultHookSet(_hook);
    }

    /**
     * @notice Sets the required post dispatch hook for the Mailbox.
     * @param _hook The new default post dispatch hook. Must be a contract.
     */
    function setRequiredHook(address _hook) public onlyOwner {
        require(Address.isContract(_hook), "Mailbox: !contract");
        requiredHook = IPostDispatchHook(_hook);
        emit RequiredHookSet(_hook);
    }

    /**
     * @notice Returns the ISM to use for the recipient, defaulting to the
     * default ISM if none is specified.
     * @param _recipient The message recipient whose ISM should be returned.
     * @return The ISM to use for `_recipient`.
     */
    function recipientIsm(address _recipient)
        public
        view
        returns (IInterchainSecurityModule)
    {
        // Use a default interchainSecurityModule if one is not specified by the
        // recipient.
        // This is useful for backwards compatibility and for convenience as
        // recipients are not mandated to specify an ISM.
        try
            ISpecifiesInterchainSecurityModule(_recipient)
                .interchainSecurityModule()
        returns (IInterchainSecurityModule _val) {
            // If the recipient specifies a zero address, use the default ISM.
            if (address(_val) != address(0)) {
                return _val;
            }
            // solhint-disable-next-line no-empty-blocks
        } catch {}
        return defaultIsm;
    }
}
