// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@rari-capital/solmate/src/tokens/ERC721.sol";

import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Kodex Exchange
/// @author Quantumlyy (https://github.com/quantumlyy)
contract KodexExchange is Ownable, EIP712 {
	//////////////////////////////////////////////////////////////////////////////////////
	///                                EIP712 CONSTANTS                                ///
	//////////////////////////////////////////////////////////////////////////////////////

	bytes32 public constant _LIST_TYPEHASH = keccak256("List(uint256 tokenId,uint128 askPrice,uint120 duration)");

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

	/// @dev System fee in %. Example: 10 => 1%, 25 => 2,5%, 300 => 30%
	uint96 private systemFeePerMille;

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

	////////////////////////////////////
	///            EVENTS            ///
	////////////////////////////////////

	event NameListed(address indexed owner, uint256 indexed tokenId, uint128 askPrice, uint128 duration);

	event NameRemoved(uint256 indexed tokenId);

	event NamePurchased(address indexed owner, address indexed buyer, uint256 indexed tokenId, uint128 askPrice);

	event NameOfferPlaced(address indexed offerer, uint256 indexed tokenId, uint128 offerAmount, uint128 duration);

	event NameOfferPulled(uint256 indexed tokenId, address indexed offerer);

	event NameOfferAccepted(address indexed owner, address indexed offerer, uint256 indexed tokenId, uint128 offerAmount);

	////////////////////////////////////////////////////////////////////////////
	///                            INITIALIZATION                            ///
	////////////////////////////////////////////////////////////////////////////

	/// @param _ensAddress address of the ENS registrar.
	constructor(
		address _ensAddress,
		address _weth,
		address _systemFeeWallet,
		uint96 _systemFeePerMille
	) EIP712(name, version()) {
		require(_ensAddress != address(0), "ADDRESS_REGISTRY_INVALID");
		ensRegistry = ERC721(_ensAddress);
		require(_weth != address(0), "ADDRESS_WETH_INVALID");
		WETH = IERC20(_weth);

		systemFeeWallet = _systemFeeWallet;
		systemFeePerMille = _systemFeePerMille;
	}

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	///                                                EXTENRAL ORDER FUNCTIONS                                                ///
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	// solhint-disable-next-line func-name-mixedcase
	function list_i52(
		uint256 _tokenId,
		uint128 _askPrice,
		uint128 _duration
	) external payable {
		return _list_LkT(msg.sender, _tokenId, _askPrice, _duration);
	}

	// solhint-disable-next-line func-name-mixedcase
	function listBySig_m7b(
		uint256 _tokenId,
		uint128 _askPrice,
		uint120 _duration,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external payable {
		bytes32 structHash = keccak256(abi.encode(_LIST_TYPEHASH, _tokenId, _askPrice, _duration));
		bytes32 hash = _hashTypedDataV4(structHash);

		address signer = ECDSA.recover(hash, v, r, s);
		require(signer != address(0), "SIGNATURE_INVALID");

		return _list_LkT(signer, _tokenId, _askPrice, _duration);
	}

	function offer(
		uint256 _tokenId,
		uint128 _offerAmount,
		uint128 _duration
	) external payable {
		return _offer(msg.sender, _tokenId, _offerAmount, _duration);
	}

	function cancelListing(uint256 _tokenId) public payable {
		require(listings[_tokenId].tokenOwner == msg.sender, "SENDER_NOT_OWNER");

		_cancelListing(_tokenId);
	}

	function pullOffer(uint256 _tokenId) public payable {
		_cancelOffer(msg.sender, _tokenId);
	}

	function buy(uint256 _tokenId) public payable {
		Listing memory listing = listings[_tokenId];

		require(listing.tokenOwner != address(0), "LISTING_NOT_EXIST");
		require(msg.value >= listing.askPrice, "MISSING_PAYMENT");

		// solhint-disable-next-line not-rely-on-time
		if (block.timestamp > listing.duration) {
			_cancelListing(_tokenId);
			revert("EXPIRED");
		}

		if (ensRegistry.ownerOf(_tokenId) != listing.tokenOwner) {
			_cancelListing(_tokenId);
			revert("LISTING_ASSET_NOT_OWNED");
		}

		if (!ensRegistry.isApprovedForAll(listing.tokenOwner, address(this))) {
			_cancelListing(_tokenId);
			revert("LISTING_NOT_APPROVED");
		}

		uint128 systemFeePayout = systemFeeWallet != address(0) ? (listing.askPrice / 1000) * systemFeePerMille : 0;
		uint128 remainingPayout = listing.askPrice - systemFeePayout;

		if (systemFeePayout > 0) SafeTransferLib.safeTransferETH(systemFeeWallet, systemFeePayout);
		if (remainingPayout > 0) SafeTransferLib.safeTransferETH(listing.tokenOwner, remainingPayout);

		ensRegistry.safeTransferFrom(listing.tokenOwner, msg.sender, _tokenId);

		_cancelListing(_tokenId);
		emit NamePurchased(listing.tokenOwner, msg.sender, _tokenId, listing.askPrice);
	}

	function accept(uint256 _tokenId, address _offerer) public payable {
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
		uint128 systemFeePayout = systemFeeWallet != address(0) ? (amount / 1000) * systemFeePerMille : 0;
		uint128 remainingPayout = amount - systemFeePayout;

		if (systemFeePayout > 0) WETH.transferFrom(_offerer, systemFeeWallet, systemFeePayout);
		if (remainingPayout > 0) WETH.transferFrom(_offerer, msg.sender, remainingPayout);

		ensRegistry.safeTransferFrom(msg.sender, _offerer, _tokenId);

		_cancelOffer(_offerer, _tokenId);
		emit NameOfferAccepted(msg.sender, _offerer, _tokenId, amount);
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
	/// @param _newSystemFeePerMille New fee amount.
	function setSystemFeePerMille(uint96 _newSystemFeePerMille) external onlyOwner {
		systemFeePerMille = _newSystemFeePerMille;
	}

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	///                                                INTERNAL ORDER FUNCTIONS                                                ///
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	// solhint-disable-next-line func-name-mixedcase
	function _list_LkT(
		address _seller,
		uint256 _tokenId,
		uint128 _askPrice,
		uint128 _duration
	) private {
		// solhint-disable-next-line not-rely-on-time
		require(block.timestamp < _duration, "LISTING_EXPIRED");
		require(ensRegistry.ownerOf(_tokenId) == _seller, "LISTING_ASSET_NOT_OWNED");
		require(ensRegistry.isApprovedForAll(_seller, address(this)), "LISTING_NOT_APPROVED");

		Listing storage listing = listings[_tokenId];
		listing.askPrice = _askPrice;
		listing.duration = _duration;
		listing.tokenOwner = _seller;

		// solhint-disable-next-line no-inline-assembly
		assembly {
			mstore(0, _askPrice)
			mstore(0x20, _duration)
			log3(
				0,
				0x40,
				// NameListed(address,uint256,uint128,uint128)
				0xf6a4d4420dca02196de393dd446a2209d44d58a444517653ac0591be2be2a7b8,
				_seller,
				_tokenId
			)
		}
	}

	function _offer(
		address _offerer,
		uint256 _tokenId,
		uint128 _offerAmount,
		uint128 _duration
	) private {
		// solhint-disable-next-line not-rely-on-time
		require(block.timestamp < _duration, "OFFER_EXPIRED");
		require(WETH.allowance(_offerer, address(this)) >= _offerAmount, "OFFER_ALLOWANCE_LOW");

		Offer storage __offer = offers[formOfferKey(_tokenId, _offerer)];
		__offer.offerAmount = _offerAmount;
		__offer.duration = _duration;

		emit NameOfferPlaced(_offerer, _tokenId, _offerAmount, _duration);
	}

	function _cancelListing(uint256 _tokenId) private {
		emit NameRemoved(_tokenId);
		delete listings[_tokenId];
	}

	function _cancelOffer(address _offerer, uint256 _tokenId) private {
		emit NameOfferPulled(_tokenId, _offerer);
		delete offers[formOfferKey(_tokenId, _offerer)];
	}

	///////////////////////////////////////////////////////////////////////////////////////////////////////////////
	///                                          INFORMATIVE FUNCTIONS                                          ///
	///////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function version() public pure returns (string memory) {
		return "0";
	}
}