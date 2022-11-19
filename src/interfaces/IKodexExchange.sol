// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IKodexExchange {
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

    event NameOfferCreated(
        address indexed owner, address indexed offerer, uint256 indexed tokenId, uint128 offerAmount, uint128 duration
    );

    event NameOfferRemoved(uint256 indexed tokenId, address indexed offerer);

    event NameOfferExecuted(
        address indexed owner, address indexed offerer, uint256 indexed tokenId, uint128 offerAmount
    );
}
