// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/tokens/ERC721.sol";
import "solmate/tokens/ERC20.sol";
import {console2} from "forge-std/Test.sol";
import {SignUtils} from "./libraries/SignUtils.sol";
import {FractionToken} from "./ERC20Mock.sol";

contract Marketplace {
    FractionToken fractionToken;

    struct Listing {
        address token;
        uint256 tokenId;
        uint256 price;
        bytes signature;
        // Slot 4
        uint88 deadline;
        address owner;
        bool active;
        address fractionToken;
        uint256 fractionCount;
        uint256 fractionPrice;
    }

    mapping(uint256 => Listing) public listings;
    address public admin;
    uint256 public listingId;

    /* ERRORS */
    error NotOwner();
    error NotApproved();
    error MinPriceTooLow();
    error DeadlineTooSoon();
    error MinDurationNotMet();
    error InvalidSignature();
    error ListingNotExistent();
    error ListingNotActive();
    error ListingExpired();
    error FractionPriceNotMet(int256 difference);
    error FractionPriceMismatch(uint256 originalPrice);

    /* EVENTS */
    event ListingCreated(uint256 indexed listingId, Listing);
    event ListingExecuted(uint256 indexed listingId, Listing);
    event ListingEdited(uint256 indexed listingId, Listing);

    constructor() {}

    function createOrder(Listing calldata l) public returns (uint256 lId) {
        if (ERC721(l.token).ownerOf(l.tokenId) != msg.sender) revert NotOwner();
        if (!ERC721(l.token).isApprovedForAll(msg.sender, address(this)))
            revert NotApproved();
        if (l.price < 0.01 ether) revert MinPriceTooLow();
        if (l.deadline < block.timestamp) revert DeadlineTooSoon();
        if (l.deadline - block.timestamp < 60 minutes)
            revert MinDurationNotMet();

        // Assert signature
        if (
            !SignUtils.isValid(
                SignUtils.constructMessageHash(
                    l.token,
                    l.tokenId,
                    l.price,
                    l.deadline,
                    l.owner
                ),
                l.signature,
                msg.sender
            )
        ) revert InvalidSignature();

        // append to Storage - Create a struct pointer
        Listing storage li = listings[listingId];
        li.token = l.token;
        li.tokenId = l.tokenId;
        li.price = l.price;
        li.signature = l.signature;
        li.deadline = uint88(l.deadline);
        li.owner = msg.sender;
        li.active = true;
        li.fractionCount = l.fractionCount;
        li.fractionPrice = l.fractionPrice;
        li.fractionToken = l.fractionToken;

        // Mint the equivalent of the amount of the token in ERC20 tokens
        FractionToken(l.fractionToken).mint(
            address(li.fractionToken),
            l.fractionPrice * l.fractionCount
        );

        // Emit event
        emit ListingCreated(listingId, l);
        lId = listingId;
        listingId++;
        return lId;
    }

    function executeOrder(uint256 _orderId) public payable {
        if (_orderId >= listingId) revert ListingNotExistent();
        Listing storage order = listings[_orderId];
        if (order.deadline < block.timestamp) revert ListingExpired();
        if (!order.active) revert ListingNotActive();
        if (order.fractionPrice < msg.value)
            revert FractionPriceMismatch(order.fractionPrice);
        if (order.fractionPrice != msg.value)
            revert FractionPriceNotMet(
                int256(order.fractionPrice) - int256(msg.value)
            );

        // Update state
        order.active = false;

        // Mint an ERC20 token to the user of the amount the NFT is for.
        FractionToken(order.fractionToken).mint(msg.sender, msg.value);
        // Burn the equivalent of the ERC20 token minted to the caller
        FractionToken(order.fractionToken).burn(msg.value);

        // calculate 0.1% of the purchased amount
        uint platformAmount = (order.fractionPrice * 1) / 1000;

        // transfer eth
        payable(order.owner).transfer(order.fractionPrice - platformAmount);

        // Update storage
        emit ListingExecuted(_orderId, order);
    }

    function transferMyFraction(uint256 _orderId, address _to) public {
        Listing storage order = listings[_orderId];
        payable(_to).transfer(order.fractionPrice);
    }

    function editOrder(
        uint256 _orderId,
        uint256 _newPrice,
        bool _active
    ) public {
        if (_orderId >= listingId) revert ListingNotExistent();
        Listing storage order = listings[_orderId];
        if (order.owner != msg.sender) revert NotOwner();
        order.price = _newPrice;
        order.active = _active;
        emit ListingEdited(_orderId, order);
    }

    // add getter for order
    function getOrder(uint256 _orderId) public view returns (Listing memory) {
        // if (_orderId >= listingId)
        return listings[_orderId];
    }
}
