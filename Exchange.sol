// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {LinkedListLibrary, LinkedList} from "./LinkedList.sol";

using LinkedListLibrary for LinkedList;

struct Request {
    address account;
    uint128 id;
    uint32 price;
    int64 amount;
    uint32 deadline;
}

struct Limiter {
    uint256 interval;
    uint256 limit;
}

//TODO: custom events

function floorDiv(int256 a, int256 b) pure returns (int256 quotient) {
    quotient = a / b;
    int256 remainder = a % b;
    if (remainder != 0 && ((a < 0) != (b < 0))) {
        quotient--;
    }
}

contract Exchange is Ownable {
    IERC20 public immutable base;
    IERC20 public immutable quote;
    address public immutable vault;
    uint256 public constant decimals = 6;
    uint64 miniumumAmount = 1000000000;

    LinkedList requestIds;
    mapping(uint128 => Request) requests;

    constructor(address owner, IERC20 _base, IERC20 _quote, address _inventory) Ownable(owner) {
        base = _base;
        quote = _quote;
        vault = _inventory;
    }

    function requestTrade(uint32 _price, int64 _amount, uint32 _deadline) public {
        requestTrade(msg.sender, _price, _amount, _deadline);
    }

    function requestTrade(address _account, uint32 _price, int64 _amount, uint32 _deadline) public {
        uint128 id = requestIds.generate();
        if (_amount > 0) {
            require(uint64(_amount) >= miniumumAmount, "Amount too low");
        } else {
            require(uint64(-_amount) >= miniumumAmount, "Amount too low");
        }
        requests[id] = Request({id: id, price: _price, amount: _amount, deadline: _deadline, account: _account});
        emit RequestTrade(_account, id, _price, _amount, _deadline);
    }

    function cancelTrade(uint128 _requestId) public {
        Request storage request = requests[_requestId];
        require(request.account == msg.sender, "Not owner");
        requestIds.remove(_requestId);
        delete requests[_requestId];
        emit CancelTrade(msg.sender, _requestId);
    }

    function acceptTrade(uint128 _requestId, uint32 _price) public onlyOwner {
        Request storage request = requests[_requestId];
        require(request.deadline > block.timestamp, "Request expired");

        int256 baseAmount = request.amount;
        int256 quoteAmount = floorDiv(-baseAmount * int256(uint256(_price)), int256(10 ** decimals));

        if (baseAmount > 0) {
            require(_price <= request.price, "Price too high");
            base.transferFrom(vault, request.account, uint256(baseAmount));
        } else {
            require(_price >= request.price, "Price too low");
            base.transferFrom(request.account, vault, uint256(-baseAmount));
        }

        if (quoteAmount > 0) {
            quote.transferFrom(vault, request.account, uint256(quoteAmount));
        } else {
            quote.transferFrom(request.account, vault, uint256(-quoteAmount));
        }

        requestIds.remove(_requestId);
        delete requests[_requestId];

        emit AcceptTrade(request.account, _requestId, _price);
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

    /**
     * @dev Emitted when a trade is requested.
     */
    event RequestTrade(address indexed account, uint128 indexed id, uint32 price, int64 amount, uint32 deadline);

    /**
     * @dev Emitted when a trade is cancelled.
     */
    event CancelTrade(address indexed account, uint128 indexed id);

    /**
     * @dev Emitted when a trade is accepted.
     */
    event AcceptTrade(address indexed account, uint128 indexed id, uint32 price);
}
