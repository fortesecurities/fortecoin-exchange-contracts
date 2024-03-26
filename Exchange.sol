// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ExtendedAccessControlUpgradeable} from "./ExtendedAccessControlUpgradeable.sol";
import {WhitelistableUpgradeable} from "./WhitelistableUpgradeable.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Exchange is EIP712, Nonces, WhitelistableUpgradeable, ExtendedAccessControlUpgradeable {
    struct TradeParams {
        address account;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 minimumAmountOut;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    error InvalidSigner(address signer, address account);
    error DeadlineExpired(uint256 deadline, uint256 timestamp);
    error AmountTooLow(uint256 amount, uint256 minimumAmount);
    error BeneficiaryAlreadyExists(IERC20 token, address beneficiary);
    error BeneficiaryNotDefined(IERC20 token, address beneficiary);

    event AddBeneficiary(IERC20 indexed token, address indexed beneficiary);
    event RemoveBeneficiary(IERC20 indexed token, address indexed beneficiary);
    event Transfer(IERC20 indexed token, address indexed to, uint256 amount);
    event Trade(
        address indexed account,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    bytes32 public constant BENEFICIARY_ROLE = keccak256("BENEFICIARY_ROLE");
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    bytes32 public constant TRADE_ROLE = keccak256("TRADE_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");

    bytes32 public constant TRADE_TYPEHASH =
        keccak256(
            "Trade(address account,address tokenIn,address tokenOut,uint256 amountIn,uint256 minimumAmountOut,uint256 nonce,uint256 deadline)"
        );

    mapping(IERC20 => mapping(address => bool)) private _beneficiaries;

    constructor() EIP712("Exchange", "1") {
        _disableInitializers();
    }

    function initialize(address defaultAdmin) public initializer {
        __ExtendedAccessControl_init();
        __Whitelistable_init();
        _addRole(BENEFICIARY_ROLE);
        _addRole(TRADE_ROLE);
        _addRole(TRANSFER_ROLE);
        _addRole(WHITELIST_ROLE);
        _grantRoles(defaultAdmin);
    }

    function trade(TradeParams memory params) public onlyRole(TRADE_ROLE) whitelisted(params.account) {
        if (block.timestamp > params.deadline) {
            revert DeadlineExpired(params.deadline, block.timestamp);
        }
        if (params.amountOut < params.minimumAmountOut) {
            revert AmountTooLow(params.amountOut, params.minimumAmountOut);
        }
        bytes32 structHash = keccak256(
            abi.encode(
                TRADE_TYPEHASH,
                params.account,
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                params.minimumAmountOut,
                _useNonce(params.account),
                params.deadline
            )
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, params.v, params.r, params.s);
        if (signer != params.account) {
            revert InvalidSigner(signer, params.account);
        }
        params.tokenIn.transferFrom(params.account, address(this), params.amountIn);
        params.tokenOut.transfer(params.account, params.amountOut);
        emit Trade(params.account, params.tokenIn, params.tokenOut, params.amountIn, params.amountOut, block.timestamp);
    }

    function unWhitelist(address account) public onlyRole(WHITELIST_ROLE) {
        _unWhitelist(account);
    }

    function whitelist(address account) public onlyRole(WHITELIST_ROLE) {
        _whitelist(account);
    }

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    function isBeneficiary(IERC20 token, address account) public view returns (bool) {
        return _beneficiaries[token][account];
    }

    function addBeneficiary(IERC20 token, address beneficiary) public onlyRole(BENEFICIARY_ROLE) {
        if (isBeneficiary(token, beneficiary)) {
            revert BeneficiaryAlreadyExists(token, beneficiary);
        }
        _beneficiaries[token][beneficiary] = true;
        emit AddBeneficiary(token, beneficiary);
    }

    function removeBeneficiary(IERC20 token, address beneficiary) public onlyRole(BENEFICIARY_ROLE) {
        if (!isBeneficiary(token, beneficiary)) {
            revert BeneficiaryNotDefined(token, beneficiary);
        }
        delete _beneficiaries[token][beneficiary];
        emit RemoveBeneficiary(token, beneficiary);
    }

    function transfer(IERC20 token, address to, uint256 amount) public onlyRole(TRANSFER_ROLE) {
        if (!isBeneficiary(token, to)) {
            revert BeneficiaryNotDefined(token, to);
        }
        token.transfer(to, amount);
        emit Transfer(token, to, amount);
    }
}
