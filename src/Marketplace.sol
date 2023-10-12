// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/tokens/ERC721.sol";
import "solmate/tokens/ERC20.sol";
import {SignUtils} from "./libraries/SignUtils.sol";
import {fractionToken} from "./ERC20Mock.sol";

contract Marketplace {
    struct Order {
        address token;
        uint256 tokenId;
        uint256 price;
        bytes signature;
        // Slot 4
        uint88 deadline;
        address owner;
        bool active;
        uint256 fractionCount;
        uint256 fractionPrice;
    }

    mapping(uint256 => Order) public orders;
    address public admin;
    uint256 public orderId;

    /* ERRORS */
    error NotOwner();
    error NotApproved();
    error MinPriceTooLow();
    error DeadlineTooSoon();
    error MinDurationNotMet();
    error InvalidSignature();
    error OrderNotExistent();
    error OrderNotActive();
    error OrderExpired();
    error FractionPriceNotMet(int256 difference);
    error FractionPriceMismatch(uint256 originalPrice);

    /* EVENTS */
    event OrderCreated(uint256 indexed orderId, Order);
    event OrderExecuted(uint256 indexed orderId, Order);
    event OrderEdited(uint256 indexed orderId, Order);

    constructor() {}

    function createOrder(Order calldata l) public returns (uint256 lId) {
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
        Order storage li = orders[orderId];
        li.token = l.token;
        li.tokenId = l.tokenId;
        li.price = l.price;
        li.signature = l.signature;
        li.deadline = uint88(l.deadline);
        li.owner = msg.sender;
        li.active = true;
        li.fractionCount = l.fractionCount;
        li.fractionPrice = l.fractionPrice;

        // Mint the equivalent of the amount of the token in ERC20 tokens
        fractionToken(order.token).mint(
            address(this),
            l.fractionPrice * l.fractionCount
        );

        // Emit event
        emit OrderCreated(orderId, l);
        lId = orderId;
        orderId++;
        return lId;
    }

    function buyFractionNFT(uint256 _orderId) public payable {
        if (_orderId >= orderId) revert OrderNotExistent();
        Order storage order = orders[_orderId];
        if (order.deadline < block.timestamp) revert OrderExpired();
        if (!order.active) revert OrderNotActive();
        // if (order.price < msg.value) revert PriceMismatch(order.price);
        // if (order.price != msg.value)
        //     revert PriceNotMet(int256(order.price) - int256(msg.value));
        if (order.fractionPrice < msg.value)
            revert FractionPriceMismatch(order.fractionPrice);
        if (order.fractionPrice != msg.value)
            revert FractionPriceNotMet(
                int256(order.fractionPrice) - int256(msg.value)
            );

        // Update state
        order.active = false;

        // transfer
        // ERC721(order.token).transferFrom(
        //     order.owner,
        //     msg.sender,
        //     order.tokenId
        // );

        // Mint an ERC20 token to the user of the amount the NFT is for.
        fractionToken(order.token).mint(msg.sender, msg.value);
        // Burn the equivalent of the ERC20 token minted to the caller
        fractionToken(order.token).burn(address(this), msg.value);

        // ERC721(order.token).transferFrom(order.owner, msg.sender, order.tokenId);

        // calculate 0.1% of the purchased amount
        uint platformAmount = (order.fractionPrice * 1) / 1000;

        // transfer eth
        payable(order.owner).transfer(order.fractionPrice - platformAmount);

        // Update storage
        emit OrderExecuted(_orderId, order);
    }

    function editOrder(
        uint256 _orderId,
        uint256 _newPrice,
        bool _active
    ) public {
        if (_orderId >= orderId) revert OrderNotExistent();
        Order storage order = orders[_orderId];
        if (order.owner != msg.sender) revert NotOwner();
        order.price = _newPrice;
        order.active = _active;
        emit OrderEdited(_orderId, order);
    }

    // add getter for order
    function getOrder(uint256 _orderId) public view returns (Order memory) {
        // if (_orderId >= orderId)
        return orders[_orderId];
    }
}
