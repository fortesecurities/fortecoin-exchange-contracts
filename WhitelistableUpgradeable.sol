// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract WhitelistableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:fortesecurities.WhitelistableUpgradeable
    struct WhitelistableUpgradeableStorage {
        mapping(address => bool) whitelisted;
    }

    // keccak256(abi.encode(uint256(keccak256("fortesecurities.WhitelistableUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WhitelistableUpgradeableStorageLocation =
        0x8ab55fca81cbf05789759a1d5c24adeef4c34c7a8ed419e98684dda62bf23900;

    function _getWhitelistableUpgradeableStorage() private pure returns (WhitelistableUpgradeableStorage storage $) {
        assembly {
            $.slot := WhitelistableUpgradeableStorageLocation
        }
    }

    error NotWhitelisted(address account);

    function __Whitelistable_init() internal onlyInitializing {
        __Whitelistable_init_unchained();
    }

    function __Whitelistable_init_unchained() internal onlyInitializing {}

    /**
     * @dev Emitted when an `account` is whitelisted.
     */
    event Whitelist(address indexed account);

    /**
     * @dev Emitted when an `account` is removed from the whitelist.
     */
    event UnWhitelist(address indexed account);

    /**
     * @dev Throws if argument account is whitelisted
     * @param account The address to check
     */
    modifier whitelisted(address account) {
        if (!isWhitelisted(account)) {
            revert NotWhitelisted(account);
        }
        _;
    }

    /**
     * @dev Checks if account is whitelisted
     * @param account The address to check
     */
    function isWhitelisted(address account) public view returns (bool) {
        WhitelistableUpgradeableStorage storage $ = _getWhitelistableUpgradeableStorage();
        return $.whitelisted[account];
    }

    /**
     * @dev Adds account to whitelist
     * @param account The address to whitelist
     */
    function _whitelist(address account) internal virtual {
        WhitelistableUpgradeableStorage storage $ = _getWhitelistableUpgradeableStorage();
        $.whitelisted[account] = true;
        emit Whitelist(account);
    }

    /**
     * @dev Removes account from whitelist
     * @param account The address to remove from the whitelist
     */
    function _unWhitelist(address account) internal virtual {
        WhitelistableUpgradeableStorage storage $ = _getWhitelistableUpgradeableStorage();
        $.whitelisted[account] = false;
        emit UnWhitelist(account);
    }
}
