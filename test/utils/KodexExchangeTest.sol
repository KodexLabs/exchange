// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {KodexExchange} from "../../src/KodexExchange.sol";

abstract contract KodexExchangeTest is Test {
    using stdStorage for StdStorage;

    MockERC20 internal weth;

    KodexExchange internal exchange;

    function setUp() public virtual {
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
    }
}
