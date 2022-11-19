// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.11;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title KodexExchange
 * @notice The core contract of the Kodex exchange.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~####################################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~####################################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~####################################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~####################################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~############~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~####################################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~####################################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~####################################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~####################################~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

contract KodexExchange is Ownable, EIP712, Pausable {
	using Counters for Counters.Counter;

	//////////////////////////////////////////////////////////////////////////////////////
	///                                EIP712 CONSTANTS                                ///
	//////////////////////////////////////////////////////////////////////////////////////

	bytes32 public constant _LIST_TYPEHASH = keccak256("List(address seller,uint256 tokenId,uint128 askPrice,uint128 duration,uint256 nonce)");

	///////////////////////////////////////////////////////////////////////////////////////////
	///                                  CONTRACT METADATA                                  ///
	///////////////////////////////////////////////////////////////////////////////////////////

	// solhint-disable-next-line const-name-snakecase
	string public constant name = "Kodex ENS Exchange";

	///////////////////////////////////////////////////
	///                  CONSTANTS                  ///
	///////////////////////////////////////////////////

	ERC721 public immutable ensRegistry;
	// solhint-disable-next-line var-name-mixedcase
	IERC20 public immutable WETH;

	////////////////////////////////////////////////////////
	///                    SYSTEM FEE                    ///
	////////////////////////////////////////////////////////

	/// @dev The wallet address to which system fees get paid.
	address private systemFeeWallet;

	/// @dev System fee in %. Example: 10 => 0,1%, 25 => 0,25%, 300 => 3,0%
	uint96 private systemFeePerStep;

	uint16 private systemFeeStep;

	////////////////////////////////
	///          ORDERS          ///
	////////////////////////////////

	struct Listing {
		uint128 askPrice;
		uint128 duration;
		address tokenOwner;
	}

	/// @notice an indexed list of listings.
	mapping(uint256 => Listing) public listings;

	struct Offer {
		uint128 offerAmount;
		uint128 duration;
	}

	mapping(bytes32 => Offer) public offers;

	mapping(bytes32 => bool) public expiredSignatures;

	mapping(address => Counters.Counter) private _nonces;

	////////////////////////////////////
	///            EVENTS            ///
	////////////////////////////////////

	event NameListingCreated(address indexed owner, uint256 indexed tokenId, uint128 askPrice, uint128 duration);

	event NameListingRemoved(address indexed owner, uint256 indexed tokenId);

	event NameSignatureListingRemoved(
		address indexed owner,
		uint256 indexed tokenId,
		uint128 askPrice,
		uint128 duration,
		uint256 nonce,
		address indexed remover
	);

	event NameListingExecuted(address indexed owner, address indexed buyer, uint256 indexed tokenId, uint128 askPrice);

	event NameOfferCreated(address indexed owner, address indexed offerer, uint256 indexed tokenId, uint128 offerAmount, uint128 duration);

	event NameOfferRemoved(uint256 indexed tokenId, address indexed offerer);

	event NameOfferExecuted(address indexed owner, address indexed offerer, uint256 indexed tokenId, uint128 offerAmount);

	////////////////////////////////////////////////////////////////////////////
	///                            INITIALIZATION                            ///
	////////////////////////////////////////////////////////////////////////////

	/// @param _ensAddress address of the ENS registrar.
	constructor(
		address _ensAddress,
		address _weth,
		address _systemFeeWallet,
		uint96 _systemFeePerStep
	) EIP712(name, version()) {
		require(_ensAddress != address(0), "ADDRESS_REGISTRY_INVALID");
		ensRegistry = ERC721(_ensAddress);
		require(_weth != address(0), "ADDRESS_WETH_INVALID");
		WETH = IERC20(_weth);

		systemFeeWallet = _systemFeeWallet;
		systemFeePerStep = _systemFeePerStep;
		systemFeeStep = 10000;
	}

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	///                                                EXTERNAL ORDER FUNCTIONS                                                ///
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	// solhint-disable-next-line func-name-mixedcase
	function list(
		uint256 _tokenId,
		uint128 _askPrice,
		uint128 _duration
	) external payable whenNotPaused {
		return _list(msg.sender, _tokenId, _askPrice, _duration);
	}

	function listBySig(
		address _seller,
		uint256 _tokenId,
		uint128 _askPrice,
		uint128 _duration,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external payable whenNotPaused {
		bytes32 structHash = keccak256(abi.encode(_LIST_TYPEHASH, _seller, _tokenId, _askPrice, _duration, _useNonce(_seller)));
		bytes32 hash = _hashTypedDataV4(structHash);

		address signer = ECDSA.recover(hash, v, r, s);
		require(signer != address(0), "SIGNATURE_INVALID");
		require(expiredSignatures[hash] == false, "SIGNATURE_EXPIRED");

		_list(signer, _tokenId, _askPrice, _duration);

		expiredSignatures[hash] = true;
	}

	function offer(
		uint256 _tokenId,
		uint128 _offerAmount,
		uint128 _duration
	) external payable whenNotPaused {
		return _offer(msg.sender, _tokenId, _offerAmount, _duration);
	}

	function cancelListing(uint256 _tokenId) external payable {
		require(listings[_tokenId].tokenOwner == msg.sender, "SENDER_NOT_OWNER");

		_cancelListing(msg.sender, _tokenId);
	}

	function cancelSignature(
		address _seller,
		uint256 _tokenId,
		uint128 _askPrice,
		uint128 _duration
	) external payable {
		bytes32 structHash = keccak256(abi.encode(_LIST_TYPEHASH, _seller, _tokenId, _askPrice, _duration, nonces(_seller)));
		bytes32 hash = _hashTypedDataV4(structHash);

		expiredSignatures[hash] = true;

		emit NameSignatureListingRemoved(_seller, _tokenId, _askPrice, _duration, nonces(_seller), msg.sender);
	}

	function pullOffer(uint256 _tokenId) external payable {
		_cancelOffer(msg.sender, _tokenId);
	}

	function buyWithSig(
		address _seller,
		uint256 _tokenId,
		uint128 _askPrice,
		uint120 _duration,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external payable whenNotPaused {
		// solhint-disable-next-line not-rely-on-time
		require(block.timestamp < _duration, "LISTING_EXPIRED");

		bytes32 structHash = keccak256(abi.encode(_LIST_TYPEHASH, _seller, _tokenId, _askPrice, _duration, _useNonce(_seller)));
		bytes32 hash = _hashTypedDataV4(structHash);

		address signer = ECDSA.recover(hash, v, r, s);
		require(signer != address(0), "SIGNATURE_INVALID");
		require(expiredSignatures[hash] == false, "SIGNATURE_EXPIRED");

		require(ensRegistry.ownerOf(_tokenId) == signer, "LISTING_ASSET_NOT_OWNED");
		require(ensRegistry.isApprovedForAll(signer, address(this)), "LISTING_NOT_APPROVED");

		require(msg.value >= _askPrice, "MISSING_PAYMENT");

		{
			uint128 systemFeePayout = systemFeeWallet != address(0) ? (_askPrice / systemFeeStep) * systemFeePerStep : 0;
			uint128 remainingPayout = _askPrice - systemFeePayout;

			if (systemFeePayout > 0) SafeTransferLib.safeTransferETH(systemFeeWallet, systemFeePayout);
			if (remainingPayout > 0) SafeTransferLib.safeTransferETH(signer, remainingPayout);

			ensRegistry.safeTransferFrom(signer, msg.sender, _tokenId);
		}

		expiredSignatures[hash] = true;
		emit NameListingExecuted(signer, msg.sender, _tokenId, _askPrice);
	}

	function buy(uint256 _tokenId) external payable whenNotPaused {
		Listing memory listing = listings[_tokenId];

		address tokenOwner = listing.tokenOwner;
		uint128 askPrice = listing.askPrice;

		require(tokenOwner != address(0), "LISTING_NOT_EXIST");
		require(msg.value >= askPrice, "MISSING_PAYMENT");

		// solhint-disable-next-line not-rely-on-time
		if (block.timestamp > listing.duration) {
			_cancelListing(tokenOwner, _tokenId);
			revert("EXPIRED");
		}

		if (ensRegistry.ownerOf(_tokenId) != tokenOwner) {
			_cancelListing(tokenOwner, _tokenId);
			revert("LISTING_ASSET_NOT_OWNED");
		}

		if (!ensRegistry.isApprovedForAll(tokenOwner, address(this))) {
			_cancelListing(tokenOwner, _tokenId);
			revert("LISTING_NOT_APPROVED");
		}

		{
			uint128 systemFeePayout = systemFeeWallet != address(0) ? (askPrice / systemFeeStep) * systemFeePerStep : 0;
			uint128 remainingPayout = askPrice - systemFeePayout;

			if (systemFeePayout > 0) SafeTransferLib.safeTransferETH(systemFeeWallet, systemFeePayout);
			if (remainingPayout > 0) SafeTransferLib.safeTransferETH(tokenOwner, remainingPayout);

			ensRegistry.safeTransferFrom(tokenOwner, msg.sender, _tokenId);
		}

		_cancelListing(tokenOwner, _tokenId);
		emit NameListingExecuted(listing.tokenOwner, msg.sender, _tokenId, listing.askPrice);
	}

	function accept(uint256 _tokenId, address _offerer) external payable whenNotPaused {
		Offer memory __offer = offers[formOfferKey(_tokenId, _offerer)];

		require(__offer.duration >= 1, "OFFER_NOT_EXIST");
		require(ensRegistry.ownerOf(_tokenId) == msg.sender, "OFFER_ACCEPTOR_NOT_OWNER");
		require(ensRegistry.isApprovedForAll(msg.sender, address(this)), "OFFER_ACCEPTOR_NOT_APPROVED");
		require(WETH.allowance(_offerer, address(this)) >= __offer.offerAmount, "OFFER_ALLOWANCE_LOW");

		// solhint-disable-next-line not-rely-on-time
		if (block.timestamp > __offer.duration) {
			_cancelOffer(_offerer, _tokenId);
			revert("EXPIRED");
		}

		uint128 amount = __offer.offerAmount;
		uint128 systemFeePayout = systemFeeWallet != address(0) ? (amount / systemFeeStep) * systemFeePerStep : 0;
		uint128 remainingPayout = amount - systemFeePayout;

		if (systemFeePayout > 0) WETH.transferFrom(_offerer, systemFeeWallet, systemFeePayout);
		if (remainingPayout > 0) WETH.transferFrom(_offerer, msg.sender, remainingPayout);

		ensRegistry.safeTransferFrom(msg.sender, _offerer, _tokenId);

		_cancelOffer(_offerer, _tokenId);
		emit NameOfferExecuted(msg.sender, _offerer, _tokenId, amount);
	}

	function formOfferKey(uint256 _tokenId, address _offerer) public pure returns (bytes32) {
		return keccak256(abi.encode(_tokenId, _offerer));
	}

	//////////////////////////////////////////////////////////////////////////////////////////////////////////
	///                                        SYSTEM FEE FUNCTIONS                                        ///
	//////////////////////////////////////////////////////////////////////////////////////////////////////////

	/// @notice Sets the new wallet to which all system fees get paid.
	/// @param _newSystemFeeWallet Address of the new system fee wallet.
	function setSystemFeeWallet(address payable _newSystemFeeWallet) external onlyOwner {
		systemFeeWallet = _newSystemFeeWallet;
	}

	/// @notice Sets the new overall fee %. Example: 10 => 1%, 25 => 2,5%, 300 => 30%
	/// @param _newsystemFeePerStep New fee amount.
	function setsystemFeePerStep(uint96 _newsystemFeePerStep) external onlyOwner {
		systemFeePerStep = _newsystemFeePerStep;
	}

	function setsystemFeeStep(uint16 _newsystemFeeStep) external onlyOwner {
		systemFeeStep = _newsystemFeeStep;
	}

	//////////////////////////////////////////////////////////////////////////////////////////////////////////
	///                                          PAUSING FUNCTIONS                                         ///
	//////////////////////////////////////////////////////////////////////////////////////////////////////////

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	///                                                INTERNAL ORDER FUNCTIONS                                                ///
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	// solhint-disable-next-line func-name-mixedcase
	function _list(
		address _seller,
		uint256 _tokenId,
		uint128 _askPrice,
		uint128 _duration
	) internal {
		// solhint-disable-next-line not-rely-on-time
		require(block.timestamp < _duration, "LISTING_EXPIRED");
		require(ensRegistry.ownerOf(_tokenId) == _seller, "LISTING_ASSET_NOT_OWNED");
		require(ensRegistry.isApprovedForAll(_seller, address(this)), "LISTING_NOT_APPROVED");

		Listing storage listing = listings[_tokenId];
		listing.askPrice = _askPrice;
		listing.duration = _duration;
		listing.tokenOwner = _seller;

		emit NameListingCreated(_seller, _tokenId, _askPrice, _duration);
	}

	function _offer(
		address _offerer,
		uint256 _tokenId,
		uint128 _offerAmount,
		uint128 _duration
	) internal {
		// solhint-disable-next-line not-rely-on-time
		require(block.timestamp < _duration, "OFFER_EXPIRED");
		require(WETH.allowance(_offerer, address(this)) >= _offerAmount, "OFFER_ALLOWANCE_LOW");

		Offer storage __offer = offers[formOfferKey(_tokenId, _offerer)];
		__offer.offerAmount = _offerAmount;
		__offer.duration = _duration;

		emit NameOfferCreated(ensRegistry.ownerOf(_tokenId), _offerer, _tokenId, _offerAmount, _duration);
	}

	function _cancelListing(address _owner, uint256 _tokenId) internal {
		emit NameListingRemoved(_owner, _tokenId);
		delete listings[_tokenId];
	}

	function _cancelOffer(address _offerer, uint256 _tokenId) internal {
		emit NameOfferRemoved(_tokenId, _offerer);
		delete offers[formOfferKey(_tokenId, _offerer)];
	}

	function _useNonce(address owner) internal returns (uint256 current) {
		Counters.Counter storage nonce = _nonces[owner];
		current = nonce.current();
		nonce.increment();
	}

	///////////////////////////////////////////////////////////////////////////////////////////////////////////////
	///                                          INFORMATIVE FUNCTIONS                                          ///
	///////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function version() public pure returns (string memory) {
		return "0";
	}

	function nonces(address owner) public view returns (uint256) {
		return _nonces[owner].current();
	}
}
