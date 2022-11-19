// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {KodexExchangeTest, stdStorage, StdStorage} from "./utils/KodexExchangeTest.sol";

contract KodexExchangeUnitTest is KodexExchangeTest {
    using stdStorage for StdStorage;

    function testUnitInitial() public {
        assertEq(address(exchange.ensRegistry()), address(ensRegistry));
        assertEq(address(exchange.WETH()), address(weth));
    }
}
