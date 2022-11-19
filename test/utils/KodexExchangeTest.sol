// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";

import {KodexExchange} from "../../src/KodexExchange.sol";

abstract contract KodexExchangeTest is Test {
    using stdStorage for StdStorage;

    MockERC20 internal weth;
    MockERC721 internal ensRegistry;

    KodexExchange internal exchange;

    address internal constant FEE_TO = address(0xFEEE);
    uint96 internal constant FEE_PER_STEP_DEFAULT = 100;

    function setUp() public virtual {
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        ensRegistry = new MockERC721("Ethereum Name Service", "ENS");

        exchange = new KodexExchange(address(ensRegistry), address(weth), FEE_TO, FEE_PER_STEP_DEFAULT);
    }

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }
}
