// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ExtendedAccessControlUpgradeable} from "./ExtendedAccessControlUpgradeable.sol";
import {LinkedListLibrary, LinkedList} from "./LinkedList.sol";
import {Limiter, LimiterLibrary} from "./Limiter.sol";

function floorDiv(int256 a, int256 b) pure returns (int256 quotient) {
    quotient = a / b;
    int256 remainder = a % b;
    if (remainder != 0 && ((a < 0) != (b < 0))) {
        quotient--;
    }
}

contract Exchange is ExtendedAccessControlUpgradeable {
    struct Request {
        address account;
        uint128 id;
        uint32 price;
        int64 amount;
        uint32 deadline;
    }

    error SenderUnauthorized();
    error DeadlineExpired();
    error PriceTooLow();
    error PriceTooHigh();
    error AmountTooLow();
    error LimitExceeded();

    bytes32 public constant LIMIT_ROLE = keccak256("LIMIT_ROLE");
    bytes32 public constant ACCEPT_ROLE = keccak256("ACCEPT_ROLE");

    address public immutable BASE_TOKEN;
    address public immutable QUOTE_TOKEN;
    address public immutable VAULT;
    uint256 public constant PRICE_DECIMALS = 6;
    uint64 public constant MINIMUM_AMOUNT = 1000000000;

    Limiter limiter;
    using LimiterLibrary for Limiter;
    LinkedList requestIds;
    using LinkedListLibrary for LinkedList;
    mapping(uint128 => Request) requests;

    /**
     * @dev Emitted when a trade is accepted.
     */
    event AcceptTrade(address indexed account, uint128 indexed id, uint32 price);

    /**
     * @dev Emitted when the 24-hour transfer limit is changed to `limit`.
     */
    event ChangeLimit(uint256 limit);

    /**
     * @dev Emitted when a request is cancelled.
     */
    event DeleteRequest(address indexed account, uint128 indexed id);

    /**
     * @dev Emitted when a trade is requested.
     */
    event RequestTrade(address indexed account, uint128 indexed id, uint32 price, int64 amount, uint32 deadline);

    /**
     * @dev Emitted when the 24-hour transfer limit is temporarily decreased by `limitDecrease`.
     */
    event TemporarilyDecreaseLimit(uint256 limitDecrease);

    /**
     * @dev Emitted when the 24-hour transfer limit is temporarily increased by `limitIncrease`.
     */
    event TemporarilyIncreaseLimit(uint256 limitIncrease);

    constructor(address _base, address _quote, address _inventory) {
        _disableInitializers();
        BASE_TOKEN = _base;
        QUOTE_TOKEN = _quote;
        VAULT = _inventory;
    }

    function initialize(address defaultAdmin) public initializer {
        __ExtendedAccessControl_init();
        _addRole(LIMIT_ROLE);
        _addRole(ACCEPT_ROLE);
        _grantRoles(defaultAdmin);
        limiter.interval = 24 hours;
    }

    function _deleteRequest(uint128 id) internal {
        requestIds.remove(id);
        delete requests[id];
        emit DeleteRequest(msg.sender, id);
    }

    function acceptTrade(uint128 requestId, uint32 price) public onlyRole(ACCEPT_ROLE) {
        Request storage request = requests[requestId];
        if (request.deadline < block.timestamp) {
            revert DeadlineExpired();
        }

        int256 baseAmount = request.amount;
        int256 quoteAmount = computeQuoteAmount(price, baseAmount);

        if (baseAmount > 0) {
            if (price > request.price) {
                revert PriceTooHigh();
            }
            if (!limiter.addOperation(uint256(baseAmount))) {
                revert LimitExceeded();
            }
            IERC20(BASE_TOKEN).transferFrom(VAULT, request.account, uint256(baseAmount));
        } else {
            if (price < request.price) {
                revert PriceTooLow();
            }
            if (!limiter.addOperation(uint256(-baseAmount))) {
                revert LimitExceeded();
            }
            IERC20(BASE_TOKEN).transferFrom(request.account, VAULT, uint256(-baseAmount));
        }

        if (quoteAmount > 0) {
            IERC20(QUOTE_TOKEN).transferFrom(VAULT, request.account, uint256(quoteAmount));
        } else {
            IERC20(QUOTE_TOKEN).transferFrom(request.account, VAULT, uint256(-quoteAmount));
        }

        requestIds.remove(requestId);
        delete requests[requestId];

        emit AcceptTrade(request.account, requestId, price);
    }

    function cancelRequest(uint128 requestId) public {
        Request storage request = requests[requestId];
        if (request.id != 0) {
            if (request.account != msg.sender) {
                revert SenderUnauthorized();
            }
            _deleteRequest(requestId);
        }
    }

    function computeQuoteAmount(uint32 price, int256 baseAmount) public pure returns (int256) {
        return floorDiv(-baseAmount * int256(uint256(price)), int256(10 ** PRICE_DECIMALS));
    }

    function deleteExpiredRequests() public {
        uint128 id = requestIds.first();
        while (id != 0) {
            Request memory request = requests[id];
            if (request.deadline < block.timestamp) {
                _deleteRequest(id);
            }
            id = requestIds.next(id);
        }
    }

    function deleteExpiredRequests(address account) public {
        uint128 id = requestIds.first();
        while (id != 0) {
            Request memory request = requests[id];
            if (request.deadline < block.timestamp && request.account == account) {
                _deleteRequest(id);
            }
            id = requestIds.next(id);
        }
    }

    function getRequests() public view returns (Request[] memory) {
        Request[] memory _requests = new Request[](requestIds.length());
        uint128 id = requestIds.first();
        uint256 i = 0;
        while (id != 0) {
            _requests[i++] = requests[id];
            id = requestIds.next(id);
        }
        return _requests;
    }

    function requestTrade(uint32 price, int64 amount, uint32 deadline) public {
        if (deadline < block.timestamp) {
            revert DeadlineExpired();
        }
        address account = msg.sender;
        deleteExpiredRequests(account);
        uint128 id = requestIds.generate();
        if (amount > 0) {
            if (uint64(amount) < MINIMUM_AMOUNT) {
                revert AmountTooLow();
            }
        } else {
            if (uint64(-amount) < MINIMUM_AMOUNT) {
                revert AmountTooLow();
            }
        }
        requests[id] = Request({id: id, price: price, amount: amount, deadline: deadline, account: account});
        emit RequestTrade(account, id, price, amount, deadline);
    }

    function requestTradeWithPermit(
        uint32 price,
        int64 amount,
        uint32 deadline,
        uint256 value,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        address account = msg.sender;
        if (amount > 0) {
            IERC20Permit(QUOTE_TOKEN).permit(account, address(this), value, deadline, v, r, s);
        } else {
            IERC20Permit(BASE_TOKEN).permit(account, address(this), value, deadline, v, r, s);
        }
        requestTrade(price, amount, deadline);
    }

    /**
     * @dev Sets the 24-hour transfer limit.
     * Can only be called by an account with the LIMIT_ROLE.
     * @param _limit The limit value to be set.
     */
    function setLimit(uint256 _limit) public onlyRole(LIMIT_ROLE) {
        limiter.limit = _limit;
        emit ChangeLimit(_limit);
    }

    /**
     * @dev Temporarily increases the 24-hour transfer limiter.
     * Can only be called by an account with the LIMIT_ROLE.
     * @param _limitIncrease Amount by which the limit should be increased.
     */
    function temporarilyIncreaseLimit(uint256 _limitIncrease) public onlyRole(LIMIT_ROLE) {
        limiter.temporarilyIncreaseLimit(_limitIncrease);
        emit TemporarilyIncreaseLimit(_limitIncrease);
    }

    /**
     * @dev Temporarily decreases the 24-hour transfer limiter.
     * Can only be called by an account with the LIMIT_ROLE.
     * @param _limitDecrease Amount by which the limit should be decreased.
     */
    function temporarilyDecreaseLimit(uint256 _limitDecrease) public onlyRole(LIMIT_ROLE) {
        limiter.temporarilyDecreaseLimit(_limitDecrease);
        emit TemporarilyDecreaseLimit(_limitDecrease);
    }
}
