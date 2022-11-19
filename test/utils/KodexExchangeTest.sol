// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";

import {KodexExchange} from "../../src/KodexExchange.sol";

abstract contract KodexExchangeTest is Test {
    using stdStorage for StdStorage;

    KodexExchange internal exchange;
}
