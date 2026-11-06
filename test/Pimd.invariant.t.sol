// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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

    /// @dev Ensure delegated transfers of positive amounts remain reachable after arbitrary histories.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount, bool infinite)
        external
    {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 1, expectedBalance[owner]);
        uint256 permitted = infinite ? type(uint256).max : amount;
        _approve(owner, spender, permitted);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedAllowance[owner][spender] = infinite ? permitted : 0;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev The owner has enough tokens, so allowance alone must reject the spend (including self-transfers).
    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, amount - 1);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, amount - 1, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // A rejected spend must leave the entire balance/allowance model unchanged.
    }

    /// @dev Unlike overspend, this always passes the allowance check and tests its rollback.
    function rejectOverBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount, bool infinite)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        _approve(owner, spender, infinite ? type(uint256).max : amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        _approve(owner, spender, infinite ? type(uint256).max : amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    /// @dev Revocation applies even after an infinite approval. Zero-value spends must still work.
    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        _approve(owner, spender, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, 0));
    }

    /// @dev No tax, dust, new supply, or allowance change may accumulate through transfer cycles.
    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _fundedActor(fromSeed);
        address to = actors[toSeed % actors.length];
        if (to == from) {
            to = actors[(toSeed % actors.length + 1) % actors.length];
        }
        amount = bound(amount, 1, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        // Check the outward leg too: two no-op transfers would otherwise pass a round trip.
        assertEq(token.balanceOf(from), expectedBalance[from] - amount);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // Net model change is zero; the invariants check every balance and allowance afterwards.
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _fundedActor(uint256 seed) internal view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[(start + i) % actors.length];
            if (expectedBalance[actor] > 0) return actor;
        }
        revert("model lost the fixed supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PimdInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pimd internal token;
    PimdHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new Pimd();
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        handler = new PimdHandler(token, actors, SUPPLY);
        assertTrue(token.transfer(actors[0], SUPPLY));
        // Start all actors funded through real transfers; never edit token storage to prepare a case.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.move(0, i, SUPPLY / actors.length);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = PimdHandler.move.selector;
        selectors[1] = PimdHandler.approve.selector;
        selectors[2] = PimdHandler.spend.selector;
        selectors[3] = PimdHandler.overspend.selector;
        selectors[4] = PimdHandler.approveAndSpend.selector;
        selectors[5] = PimdHandler.rejectOverAllowance.selector;
        selectors[6] = PimdHandler.rejectOverBalance.selector;
        selectors[7] = PimdHandler.rejectZeroRecipient.selector;
        selectors[8] = PimdHandler.revokeAndReject.selector;
        selectors[9] = PimdHandler.roundTrip.selector;
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
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
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
