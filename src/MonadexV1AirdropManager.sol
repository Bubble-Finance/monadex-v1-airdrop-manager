// Layout:
//     - pragma
//     - imports
//     - interfaces, libraries, contracts
//     - type declarations
//     - state variables
//     - events
//     - errors
//     - modifiers
//     - functions
//         - constructor
//         - receive function (if exists)
//         - fallback function (if exists)
//         - external
//         - public
//         - internal
//         - private
//         - view and pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;



/// @title MonadexV1AirdropManager
/// @author Ola Hamid
/// @notice This contract manages the airdrop process for the Monadex protocol, utilizing a Merkle tree for efficient eligibility verification.
/// @notice Participants submit their proof of eligibility, which is verified against the Merkle root. Upon successful verification, participants can claim their airdrop tokens.

import { MerkleProof } from
    "../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

import { BitMaps } from "../lib/openzeppelin-contracts/contracts/utils/structs/BitMaps.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";


contract MonadexV1AirdropManager is EIP712, Ownable, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    /////////////////////
    ///state variables///
    /////////////////////
    /// @notice The root of the Merkle tree used for airdrop eligibility verification.
    bytes32 public merkleRoot;

    /// @notice A private BitMap to track airdrop claims.
    BitMaps.BitMap private _airdropLists;

    /// @notice A public list of eligible addresses for the airdrop.
    address[] public eligibleAddresses;

    /// @notice A private array of new tokens added to the system.
    address[] private s_Tokens;

    /// @notice The maximum number of addresses that can claim the airdrop.
    uint256 public maxAddressLimit;

    /// @notice The amount of tokens each eligible address has claim.
    uint256 public claimedAmount;

    /// @notice A public mapping to track if a token is supported for the airdrop.
    mapping(address => bool isSupported) public m_supportedToken;

    /// @notice A public mapping to store the Merkle proof for each claimant.
    mapping(address => bytes32) public m_claimProof;

    /// @notice A public mapping to track if an address has already claimed the airdrop.
    mapping(address => bool) public m_hasClaimed;

    struct monadexAirdropClaimer {
        address claimer;
        uint256 amount;
    }

    bytes32 private constant messageTypeHash = keccak256("monadexAirdropClaimer(address claimer, uint amount");

    ///////////
    ///ERROR///
    //////////
    error Monadex_UnsupportedAirdropToken(address token);
    error Monadex_ZeroAddressError();
    error Monadex_maxAddressLimit(uint256 maxAddressLimit, uint256 receiverLength);
    error Monadex_InvalidMekleproofError();
    error Monadex_HasClaimedError();
    error Monadex_sameTokenAddrAlreadyAdded();
    error Monadex_ZeroAmountError();
    error Monadex_invalidSignatureError();

    ///////////
    ///Event///
    //////////
    event E_TokenToClaim(
        address indexed token,
        uint256 indexed amount,
        address indexed claimer
        );

    event E_directTokenToclaim(
        address indexed token,
         uint256 indexed amount
         );

    event E_addAirdropfund(
        address indexed token,
        uint256 indexed amountToAdd
        );
        
    event E_addToken(
        address indexed token
        );

    constructor(
        uint256 _maxAddressLimit,
        bytes32 _merkleRoot
    )
        Ownable(msg.sender)
        EIP712("MonadexV1AirdropManager", "1")
    {
        maxAddressLimit = _maxAddressLimit;
        merkleRoot = _merkleRoot;
    }
    

    /// @notice Adds a new token to the supported list for airdrops.
    /// Ensures the token is valid and not already listed.
    /// @param newToken Token address to be added to the list.
    /// @dev Enables the contract owner to add a new token.
    /// Validates the token address and uniqueness.
    function addToken(address newToken) external onlyOwner {
        if (newToken == address(0)) {
            revert Monadex_ZeroAddressError();
        }
        //tackle that users dont add the same new token multiple times
        if (m_supportedToken[newToken] == true) {
            revert Monadex_sameTokenAddrAlreadyAdded();
        }
        m_supportedToken[newToken] = true;

        s_Tokens.push(newToken);

        emit E_addToken(newToken);
    }

    /// @notice Adds a supported token to the airdrop fund.
    /// Checks token support and prevents zero/negative amounts.
    /// @param supportedToken Token address to add to the fund.
    /// @param totalAmountToAirdrop Total amount of the token to add.
    /// @dev Allows owner to add a token to the fund.
    /// Verifies token support and non-zero amount.
    /// Transfers the token and emits an event.
    function addAirdropFund(
        address supportedToken,
        uint256 totalAmountToAirdrop
    )
        external
        nonReentrant
        onlyOwner
    {
        if (m_supportedToken[supportedToken] != true) {
            revert Monadex_UnsupportedAirdropToken(supportedToken);
        }

        IERC20 token = IERC20(supportedToken);
        if (totalAmountToAirdrop <= 0) {
            revert Monadex_ZeroAmountError();
        }
        token.safeTransferFrom(msg.sender, address(this), totalAmountToAirdrop);

        emit E_addAirdropfund(supportedToken, totalAmountToAirdrop);
    }

    
    /// @notice Distributes tokens to eligible addresses.
    /// Validates tokens and limits per address.
    /// Requires a valid Merkle proof for each recipient.
    /// @param supportedToken Token address to distribute.
    /// @param receiver Array of recipient addresses.
    /// @param _amount Amount of tokens to distribute.
    /// @param proof Merkle proof for each recipient's eligibility.
    /// @param index Leaf index in the Merkle tree for the proof.
    /// @dev Transfers tokens to recipients based on Merkle proofs.
    /// Updates airdrop list and transfers tokens.
    function directAirdrop(
        address supportedToken,
        address[] memory receiver,
        uint256[] memory _amount,
        bytes32[] calldata proof,
        uint256 index
    )
        external
        nonReentrant
        onlyOwner
        
    {
        if (m_supportedToken[supportedToken] != true) {
            revert Monadex_UnsupportedAirdropToken(supportedToken);
        }
        if (receiver.length > maxAddressLimit) {
            revert Monadex_maxAddressLimit(maxAddressLimit, receiver.length);
        }
        IERC20 token = IERC20(supportedToken);
        uint256 receiverLength = receiver.length;
        for (uint256 i = 0; i < receiverLength; ++i) {
            verifyProof(receiver[i], proof, index, _amount[i] );
            BitMaps.setTo(_airdropLists, index, true);
            token.safeTransfer(receiver[i], _amount[i]);
            claimedAmount += _amount[i];
        }

        emit E_directTokenToclaim(supportedToken, claimedAmount);
    }

    /// @notice Claims airdrop by providing a valid Merkle proof.
    /// Verifies eligibility and updates the airdrop list.
    /// @param _claimer address to claim
    /// @param _amount amount for the user to claim 
    /// @param supportedToken Token address to claim.
    /// @param proof Merkle proof for eligibility verification.
    /// @param index Leaf index in the Merkle tree for the proof.
    /// @param v v
    /// @param r r
    /// @param s s
    /// @dev Enables participants to claim their airdrop.
    /// Checks token support, proof validity, and claim status.
    /// Transfers the token and updates the airdrop list.
    function claimAirdrop(
        address _claimer,
        uint _amount,
        address supportedToken,
        bytes32[] calldata proof,
        uint256 index,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        nonReentrant
    {
        
        if (_claimer == address(0)) {
            revert Monadex_ZeroAddressError();
        }

        if (_amount == 0) {
            revert Monadex_ZeroAmountError();
        }
        
        if (m_supportedToken[supportedToken] != true) {
            revert Monadex_UnsupportedAirdropToken(supportedToken);
        }
        if (BitMaps.get(_airdropLists, index)) {
            revert Monadex_HasClaimedError();
        }
        if (isValidSignature(_claimer, getDigest(_claimer, _amount), v, r, s)) {
            revert Monadex_invalidSignatureError();
        }
        verifyProof(_claimer, proof, index, _amount);
        m_claimProof[msg.sender] = keccak256(abi.encodePacked(proof));
        claimedAmount += _amount;
        IERC20 token = IERC20(supportedToken);
        
        BitMaps.setTo(_airdropLists, index, true);
        // @audit to be fixed- what is stopping the user to claim more than the amont he is meant to claim?
        emit E_TokenToClaim(supportedToken,_amount, _claimer);
        token.safeTransfer(_claimer, _amount);
    }
    /// @notice Verifies a Merkle proof for a user's claim.
    /// Checks if the user's address is valid and the proof is correct.
    /// @param _claimer The address of the user claiming the airdrop.
    /// @param proof Merkle proof for the user's claim.
    /// @param index The index of the leaf in the Merkle tree for the proof.
    /// @param amount The amount of the airdrop being claimed.
    /// @dev Private function to validate a user's Merkle proof.
    function verifyProof(
        address _claimer,
        bytes32[] calldata proof,
        uint256 index,
        uint256 amount
    )
        private
        view
    {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_claimer, index, amount))));

        if (!MerkleProof.verify(proof, merkleRoot, leaf)) {
            revert Monadex_InvalidMekleproofError();
        }
    }

    function isValidSignature(
        address claimer, 
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns(bool) {
        (address actualSigner, ,) = ECDSA.tryRecover(digest, v, r, s);
        return (actualSigner == claimer);
    }
    /////////////////////
    ///getter function///
    /////////////////////
    /// @notice Returns the address of a new token by its ID.
    /// @param TokenID The ID of the token to retrieve.
    /// @dev Public view function to fetch a token's address by its ID.
    /// @return returns the address of the token from the mapping.
    function getNewToken(
        uint256 TokenID
        ) 
        external 
        view 
        returns (address) {
        return s_Tokens[TokenID];
    }

    /**
     * @notice Returns the bool for address have claimed or not.
     * @param _claimer address of user that have claimed
     */

   function getIfClaimedAddress(
    address _claimer
   )
   external 
   view 
   returns (bool) {
    return m_hasClaimed[_claimer];
   }

   /**
    * @notice Function checks if token address is supported or not
    * @param _isSupportedToken token address 
    */
   function getSupportedToken (
    address _isSupportedToken
   )
   external 
   view 
   returns (bool) {
    return m_supportedToken[_isSupportedToken];
   }
   function getClaimedAmount(
   ) external
   view returns(uint){
    return claimedAmount;
   }
   function getDigest(address claimer, uint amount ) public view returns (bytes32) {
    return _hashTypedDataV4(keccak256(abi.encode(messageTypeHash,
         monadexAirdropClaimer({
            claimer : claimer,
            amount : amount
         })
    )));
   }
}


