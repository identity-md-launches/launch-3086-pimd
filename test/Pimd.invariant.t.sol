// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Pimd} from "../src/Pimd.sol";

/// @dev Models balances/allowances independently while exercising sequences of ERC-20 operations.
contract PimdHandler is Test {
    Pimd public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Pimd token_, address[4] memory actors_, uint256 supply) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = supply;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 permitted = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, permitted < balance ? permitted : balance);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (permitted != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev Exercise failed transfers after arbitrary histories; the model must remain unchanged.
    function overspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[owner] + 1;

        vm.prank(owner);
        (bool transferred,) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertFalse(transferred);
        vm.prank(spender);
        (bool spent,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertFalse(spent);
    }
}

contract PimdInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pimd internal token;
    PimdHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new Pimd();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        handler = new PimdHandler(token, actors, SUPPLY);
        token.transfer(actors[0], SUPPLY);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = PimdHandler.move.selector;
        selectors[1] = PimdHandler.approve.selector;
        selectors[2] = PimdHandler.spend.selector;
        selectors[3] = PimdHandler.overspend.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixedAndEveryTokenIsAccountedFor() public view {
        uint256 accounted;
        for (uint256 i; i < actors.length; ++i) {
            accounted += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(accounted, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_balancesAndAllowancesMatchTheModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
