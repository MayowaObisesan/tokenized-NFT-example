// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Marketplace} from "../src/Marketplace.sol";
import "../src/ERC721Mock.sol";
import "../src/ERC20Mock.sol";
import "./Helpers.sol";

contract MarketPlaceTest is Helpers {
    Marketplace mPlace;
    OurNFT nft;
    FractionToken fractionToken;

    uint256 currentOrderId;

    address userA;
    address userB;

    uint256 privKeyA;
    uint256 privKeyB;

    Marketplace.Listing order;

    function setUp() public {
        mPlace = new Marketplace();
        nft = new OurNFT();
        // fractionToken = new FractionToken();

        (userA, privKeyA) = mkaddr("USERA");
        (userB, privKeyB) = mkaddr("USERB");

        order = Marketplace.Listing({
            token: address(nft),
            tokenId: 1,
            price: 1 ether,
            signature: bytes(""),
            deadline: 0,
            owner: address(0),
            active: false,
            name: "FToken",
            symbol: "FTK",
            fractionToken: address(fractionToken),
            fractionCount: 10,
            fractionPrice: 2 ether,
            fractionBought: 0
        });

        nft.mint(userA, 1);
    }

    function testOwnerCannotCreateOrder() public {
        order.owner = userB;
        switchSigner(userB);

        vm.expectRevert(Marketplace.NotOwner.selector);
        mPlace.createOrder(order);
    }

    function testNFTNotApproved() public {
        switchSigner(userA);
        vm.expectRevert(Marketplace.NotApproved.selector);
        mPlace.createOrder(order);
    }

    function testMinPriceTooLow() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.price = 0;
        vm.expectRevert(Marketplace.MinPriceTooLow.selector);
        mPlace.createOrder(order);
    }

    function testMinDeadline() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        vm.expectRevert(Marketplace.DeadlineTooSoon.selector);
        mPlace.createOrder(order);
    }

    function testMinDuration() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.deadline = uint88(block.timestamp + 59 minutes);
        vm.expectRevert(Marketplace.MinDurationNotMet.selector);
        mPlace.createOrder(order);
    }

    function testSignatureNotValid() public {
        // Test that signature is valid
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.deadline = uint88(block.timestamp + 120 minutes);
        order.signature = constructSig(
            order.token,
            order.tokenId,
            order.price,
            order.deadline,
            order.owner,
            privKeyB
        );
        vm.expectRevert(Marketplace.InvalidSignature.selector);
        mPlace.createOrder(order);
    }

    // EDIT Listing
    function testEditNonValidOrder() public {
        switchSigner(userA);
        vm.expectRevert(Marketplace.ListingNotExistent.selector);
        mPlace.editOrder(1, 0, false);
    }

    function testEditOrderNotOwner() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.deadline = uint88(block.timestamp + 120 minutes);
        order.signature = constructSig(
            order.token,
            order.tokenId,
            order.price,
            order.deadline,
            order.owner,
            privKeyA
        );
        // vm.expectRevert(Marketplace.ListingNotExistent.selector);
        uint256 newOrderId = mPlace.createOrder(order);

        switchSigner(userB);
        vm.expectRevert(Marketplace.NotOwner.selector);
        mPlace.editOrder(newOrderId, 0, false);
    }

    function testEditOrder() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.deadline = uint88(block.timestamp + 120 minutes);
        order.signature = constructSig(
            order.token,
            order.tokenId,
            order.price,
            order.deadline,
            order.owner,
            privKeyA
        );
        uint256 newOrderId = mPlace.createOrder(order);
        mPlace.editOrder(newOrderId, 0.01 ether, false);

        Marketplace.Listing memory _order = mPlace.getOrder(newOrderId);
        assertEq(_order.price, 0.01 ether);
        assertEq(_order.active, false);
    }

    // EXECUTE Listing
    function testExecuteNonValidOrder() public {
        switchSigner(userA);
        vm.expectRevert(Marketplace.ListingNotExistent.selector);
        mPlace.executeOrder(1);
    }

    function testExecuteExpiredOrder() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
    }

    function testExecuteOrderNotActive() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.deadline = uint88(block.timestamp + 120 minutes);
        order.signature = constructSig(
            order.token,
            order.tokenId,
            order.price,
            order.deadline,
            order.owner,
            privKeyA
        );
        uint256 newOrderId = mPlace.createOrder(order);
        mPlace.editOrder(newOrderId, 0.01 ether, false);
        switchSigner(userB);
        vm.expectRevert(Marketplace.ListingNotActive.selector);
        mPlace.executeOrder(newOrderId);
    }

    function testFulfilOrderPriceNotEqual() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.deadline = uint88(block.timestamp + 120 minutes);
        // order.fractionPrice = 1.2 ether;
        order.signature = constructSig(
            order.token,
            order.tokenId,
            order.price,
            order.deadline,
            order.owner,
            privKeyA
        );
        uint256 newOrderId = mPlace.createOrder(order);
        switchSigner(userB);
        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.FractionPriceNotMet.selector,
                order.fractionPrice - 0.9 ether
            )
        );
        mPlace.executeOrder{value: 0.9 ether}(newOrderId);
    }

    function testFulfilOrderPriceMismatch() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.deadline = uint88(block.timestamp + 120 minutes);
        order.signature = constructSig(
            order.token,
            order.tokenId,
            order.price,
            order.deadline,
            order.owner,
            privKeyA
        );
        uint256 newOrderId = mPlace.createOrder(order);
        switchSigner(userB);
        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.FractionPriceMismatch.selector,
                order.fractionPrice
            )
        );
        mPlace.executeOrder{value: 2.1 ether}(newOrderId);
    }

    function testFulfilOrder() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.deadline = uint88(block.timestamp + 120 minutes);
        order.signature = constructSig(
            order.token,
            order.tokenId,
            order.price,
            order.deadline,
            order.owner,
            privKeyA
        );
        uint256 newOrderId = mPlace.createOrder(order);
        switchSigner(userB);
        uint256 userABalanceBefore = userA.balance;

        mPlace.executeOrder{value: order.fractionPrice}(newOrderId);

        uint256 userABalanceAfter = userA.balance;

        Marketplace.Listing memory _order = mPlace.getOrder(newOrderId);
        assertEq(_order.price, 1 ether);
        assertEq(_order.fractionPrice, 2 ether);
        assertEq(_order.active, false);

        assertEq(_order.active, false);
        assertEq(ERC721(order.token).ownerOf(order.tokenId), userA);
        assertEq(
            userABalanceAfter,
            userABalanceBefore +
                (order.fractionPrice - ((order.fractionPrice * 1) / 1000))
        );
    }

    function testBoughtAllFraction() public {
        switchSigner(userA);
        nft.setApprovalForAll(address(mPlace), true);
        order.fractionBought = 10;
        order.deadline = uint88(block.timestamp + 120 minutes);
        order.signature = constructSig(
            order.token,
            order.tokenId,
            order.price,
            order.deadline,
            order.owner,
            privKeyA
        );
        uint256 newOrderId = mPlace.createOrder(order);
        switchSigner(userB);
        vm.expectRevert(
            abi.encodeWithSelector(
                Marketplace.FractionPriceMismatch.selector,
                order.fractionPrice
            )
        );
        mPlace.executeOrder{value: 2.1 ether}(newOrderId);
    }
}
