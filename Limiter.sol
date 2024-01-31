// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LinkedListLibrary, LinkedList} from "./LinkedList.sol";

using LinkedListLibrary for LinkedList;

struct Operation {
    int256 amount;
    uint256 timestamp;
}

struct Limiter {
    uint256 interval;
    uint256 limit;
    LinkedList _keys;
    mapping(uint128 => Operation) _operations;
}

using LimiterLibrary for Limiter;

library LimiterLibrary {
    function operations(Limiter storage self) internal view returns (Operation[] memory) {
        Operation[] memory _operations = new Operation[](self._keys.length());
        uint256 index = 0;
        uint128 key = self._keys.first();
        while (key != 0) {
            _operations[index] = self._operations[key];
            key = self._keys.next(key);
            index++;
        }
        return _operations;
    }

    function temporarilyIncreaseLimit(Limiter storage self, uint256 _limitIncrease) internal {
        _addUncheckedOperation(self, -int256(_limitIncrease));
    }

    function temporarilyDecreaseLimit(Limiter storage self, uint256 _limitDecrease) internal {
        _addUncheckedOperation(self, int256(_limitDecrease));
    }

    function remainingLimit(Limiter storage self) internal view returns (int256) {
        return int256(self.limit) - self.usedLimit();
    }

    function usedLimit(Limiter storage self) internal view returns (int256) {
        int256 _sum = 0;
        uint128 key = self._keys.first();
        while (key != 0) {
            if (self._operations[key].timestamp > block.timestamp - self.interval) {
                _sum += self._operations[key].amount;
            }
            key = self._keys.next(key);
        }
        return _sum;
    }

    function _filterOperations(Limiter storage self) private {
        uint128 key = self._keys.first();
        while (key != 0) {
            if (self._operations[key].timestamp > block.timestamp - self.interval) {
                break;
            }
            delete self._operations[key];
            key = self._keys.remove(key);
        }
    }

    function _addOperationNode(Limiter storage self, int256 _amount) private {
        uint128 key = self._keys.generate();
        self._operations[key] = Operation({amount: int256(_amount), timestamp: block.timestamp});
    }

    function _addUncheckedOperation(Limiter storage self, int256 _amount) private {
        _filterOperations(self);
        _addOperationNode(self, _amount);
    }

    function addOperation(Limiter storage self, uint256 _amount) internal returns (bool) {
        _addUncheckedOperation(self, int256(_amount));
        return self.remainingLimit() >= 0;
    }
}
