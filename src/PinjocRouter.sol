// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {MockGTXOrderBook} from "./mocks/MockGTXOrderBook.sol";
import {LendingOrderType, Status} from "./types/Types.sol";
import {IMockGTXOrderBook} from "./interfaces/IMockGTXOrderBook.sol";
import {ILendingPoolManager} from "./interfaces/ILendingPoolManager.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IMockOracle} from "./interfaces/IMockOracle.sol";
import {Uint256Library, Side} from "./types/Types.sol";

using Uint256Library for uint256;

contract PinjocRouter is Ownable, ReentrancyGuard {
    ILendingPoolManager public lendingPoolManager;
    mapping(string => address) public orderBookTokenMapping;
    mapping(string => address) public orderBookMapping;

    error InvalidAddressParameter();
    error InvalidPlaceOrderParameter();
    error BalanceNotEnough(address token, uint256 balance, uint256 amount);
    error OrderBookNotFound();
    error LendingPoolNotFound();
    error DelegateCallFailed();
    error InsufficientCollateral();

    event OrderPlaced(
        uint256 orderId,
        address debtToken,
        address collateralToken,
        uint256 amount,
        uint256 rate,
        uint256 maturity,
        string maturityMonth,
        uint256 maturityYear,
        LendingOrderType lendingOrderType,
        Status status
    );

    event OrderCancelled(uint256 orderId, Status status);

    constructor(address _lendingPoolManager) Ownable(msg.sender) {
        setLendingPoolManager(_lendingPoolManager);
    }

    function setLendingPoolManager(
        address _lendingPoolManager
    ) public onlyOwner {
        if (_lendingPoolManager == address(0)) revert InvalidAddressParameter();
        lendingPoolManager = ILendingPoolManager(_lendingPoolManager);
    }

    function createOrderBook(
        address _debtToken,
        address _collateralToken,
        string calldata _maturityMonth,
        uint256 _maturityYear
    ) external onlyOwner {
        if (_debtToken == address(0) || _collateralToken == address(0))
            revert InvalidAddressParameter();

        orderBookMapping[
            string(
                abi.encodePacked(
                    getOrderBookSymbol(_debtToken, _maturityMonth, _maturityYear),
                    getOrderBookSymbol(_collateralToken,_maturityMonth,_maturityYear)
                )
            )
        ] = address(new MockGTXOrderBook(_debtToken, _collateralToken));
    }

    function getOrderBookAddress(
        address _debtToken,
        address _collateralToken,
        string calldata _maturityMonth,
        uint256 _maturityYear
    ) public view returns (address) {
        return
            orderBookMapping[
                string(
                    abi.encodePacked(
                        getOrderBookSymbol(
                            _debtToken,
                            _maturityMonth,
                            _maturityYear
                        ),
                        getOrderBookSymbol(
                            _collateralToken,
                            _maturityMonth,
                            _maturityYear
                        )
                    )
                )
            ];
    }

    function getOrderBookSymbol(
        address _token,
        string calldata _maturityMonth,
        uint256 _maturityYear
    ) internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    IERC20Metadata(_token).symbol(),
                    _maturityMonth,
                    _maturityYear.toString()
                )
            );
    }

    function _isHealthy(
        address _debtToken,
        address _collateralToken,
        uint256 _rate,
        string calldata _maturityMonth,
        uint256 _maturityYear,
        uint256 _borrowedAmount,
        uint256 _collateralAmount
    ) internal view {
        require(
            IERC20(_collateralToken).balanceOf(msg.sender) >= _collateralAmount,
            "Balance not enough"
        );
        address lendingPoolAddress = lendingPoolManager.getLendingPool(
            _debtToken,
            _collateralToken,
            _rate,
            _maturityMonth,
            _maturityYear
        );
        if (lendingPoolAddress == address(0)) revert LendingPoolNotFound();

        uint256 collateralPrice = IMockOracle(ILendingPool(lendingPoolAddress).oracle()).price();
        uint256 collateralDecimals = 10 ** IERC20Metadata(_collateralToken).decimals();

        uint256 collateralValue = _collateralAmount * collateralPrice / collateralDecimals;
        uint256 maxBorrowValue = collateralValue * ILendingPool(lendingPoolAddress).ltv() / 1e18;

        if (_borrowedAmount > maxBorrowValue) revert InsufficientCollateral();
    }

    function placeOrder(
        address _debtToken, // lender's token - CA USDC
        address _collateralToken, // borrower's token - CA ETH
        uint256 _amount, // amount of token debt token not collateral token - 500K$
        uint256 _collateralAmount, // amount of token collateral token not debt token - 1ETH
        uint256 _rate, // APY percentage (18 decimals), e.g. for 100% pass 1e18 or 100e16, for 5% pass 5e16 - 4%
        uint256 _maturity, // maturity date in unix timestamp - 31 Maret 2025
        string calldata _maturityMonth, // MAR
        uint256 _maturityYear, // 2025
        LendingOrderType _lendingOrderType // LEND
    ) external nonReentrant {
        if (
            _debtToken == address(0) ||
            _collateralToken == address(0) ||
            _amount == 0 ||
            _rate == 0
        ) revert InvalidPlaceOrderParameter();

        address orderBookAddr = getOrderBookAddress(
            _debtToken,
            _collateralToken,
            _maturityMonth,
            _maturityYear
        );
        if (orderBookAddr == address(0)) revert OrderBookNotFound();
        IMockGTXOrderBook orderBook = IMockGTXOrderBook(orderBookAddr);

        // Send token to the order book
        if (_lendingOrderType == LendingOrderType.LEND) {
            require(
                IERC20(_debtToken).balanceOf(msg.sender) >= _amount,
                "Balance not enough"
            );
            IERC20(_debtToken).transferFrom(msg.sender, address(this), _amount);
            IERC20(_debtToken).approve(orderBookAddr, _amount);
        } else {
            _isHealthy(
                _debtToken,
                _collateralToken,
                _rate,
                _maturityMonth,
                _maturityYear,
                _amount,
                _collateralAmount
            );

            IERC20(_collateralToken).transferFrom(msg.sender, address(this), _collateralAmount);
            IERC20(_collateralToken).approve(orderBookAddr, _collateralAmount);
        }

        (
            uint256 orderId, 
            address lender, 
            address borrower, 
            uint256 debtAmount,
            uint256 borrowerAmount,
            uint256 collateralAmount,
            Status status
        ) = orderBook.placeLimitOrder(
            msg.sender,
            _amount,
            _collateralAmount,
            _rate,
            _lendingOrderType.convertToSide()
        );

        emit OrderPlaced(
            orderId,
            _debtToken,
            _collateralToken,
            _amount,
            _rate,
            _maturity,
            _maturityMonth,
            _maturityYear,
            _lendingOrderType,
            status
        );

        if (status == Status.FILLED || status == Status.PARTIALLY_FILLED) {
            address lendingPoolAddress = lendingPoolManager.getLendingPool(
                _debtToken,
                _collateralToken,
                _rate,
                _maturityMonth,
                _maturityYear
            );
            if (lendingPoolAddress == address(0)) revert LendingPoolNotFound();

            if (debtAmount < borrowerAmount) borrowerAmount = debtAmount;

            ILendingPool(lendingPoolAddress).supply(lender, debtAmount);
            ILendingPool(lendingPoolAddress).supplyCollateral(borrower, collateralAmount);
            ILendingPool(lendingPoolAddress).borrow(borrower, borrowerAmount);

            orderBook.transferFrom(lender, borrower, borrowerAmount, Side.BUY);
            orderBook.transferFrom(borrower, lendingPoolAddress, collateralAmount, Side.SELL);
        }
    }

    function cancelOrder(
        address _debtToken,
        address _collateralToken,
        string calldata _maturityMonth,
        uint256 _maturityYear,
        uint256 _orderId
    ) external nonReentrant {
        if (_orderId == 0) revert InvalidPlaceOrderParameter();

        address orderBookAddr = getOrderBookAddress(
            _debtToken,
            _collateralToken,
            _maturityMonth,
            _maturityYear
        );
        if (orderBookAddr == address(0)) revert OrderBookNotFound();
        IMockGTXOrderBook orderBook = IMockGTXOrderBook(orderBookAddr);
        orderBook.cancelOrder(msg.sender, _orderId);

        emit OrderCancelled(_orderId, Status.CANCELLED);
    }
}
