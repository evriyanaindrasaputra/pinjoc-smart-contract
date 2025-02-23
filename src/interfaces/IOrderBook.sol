// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

type Price is uint64;
type OrderId is uint48;
type Quantity is uint128;
enum Side {
    BUY,
    SELL
}

import {Status} from "../types/Types.sol";

interface IOrderBook {
    struct Order {
        OrderId id;
        address user;
        OrderId next;
        OrderId prev;
        uint48 timestamp;
        uint48 expiry;
        Price price;
        Status status;
        Quantity quantity;
        Quantity filled;
    }

    struct PriceVolume {
        Price price;
        uint256 volume;
    }

    event OrderPlaced(
        OrderId indexed orderId,
        address indexed user,
        Side indexed side,
        Price price,
        Quantity quantity,
        uint48 timestamp,
        uint48 expiry,
        bool isMarketOrder,
        Status status
    );

    event OrderCancelled(
        OrderId indexed orderId, address indexed user, uint48 timestamp, Status status
    );

    function setRouter(address router) external;

    function placeOrder(
        Price price,
        Quantity quantity,
        Side side,
        address user
    ) external returns (OrderId);

    function placeMarketOrder(
        Quantity quantity,
        Side side,
        address user
    ) external returns (OrderId);

    function cancelOrder(Side side, Price price, OrderId orderId, address user) external;

    function getOrderQueue(
        Side side,
        Price price
    ) external view returns (uint48 orderCount, uint256 totalVolume);

    function getUserActiveOrders(address user) external view returns (Order[] memory);

    function getBestPrice(Side side) external view returns (PriceVolume memory);

    function getNextBestPrices(
        Side side,
        Price price,
        uint8 count
    ) external view returns (PriceVolume[] memory);
}
