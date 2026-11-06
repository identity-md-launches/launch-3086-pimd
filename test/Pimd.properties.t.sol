// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pimd} from "src/Pimd.sol";

/// @dev Complements the deployment and ERC-20 examples in Pimd.t.sol with boundary and sequence properties.
/// forge-config: default.fuzz.runs = 1024
contract PimdPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pimd internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new Pimd();
        alice = makeAddr("property alice");
        bob = makeAddr("property bob");
        spender = makeAddr("property spender");
    }

    function test_oneWeiApprovalCanBeSpentOnlyOnce() public {
        assertTrue(token.transfer(alice, 2));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        _assertConservation();
    }

    function test_maximumFiniteAllowanceIsNotInfinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        _assertConservation();
    }

    function test_infiniteApprovalCanBeReducedThenRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        _assertConservation();
    }

    function test_maximumTransferAmountsRevertWithoutOverflow() public {
        bytes memory expected = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(expected);
        token.transfer(alice, type(uint256).max);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        _assertConservation();
    }

    function test_transferFromByOwnerStillRequiresApproval() public {
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        _assertConservation();
    }

    function test_spenderAuthorityUsesCallerNotOriginOrRecipient() public {
        assertTrue(token.transfer(alice, 3));
        vm.prank(alice);
        assertTrue(token.approve(spender, 3));

        // Neither an approved tx.origin nor an approved destination authorizes the caller.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(alice, spender, 1);
        assertEq(token.allowance(alice, spender), 3);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(spender), 0);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(spender), 0);
        _assertConservation();
    }

    function test_zeroApprovalToZeroSpenderIsInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertConservation();
    }

    function test_zeroTransferFromToZeroStillRejectsWithInfiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertConservation();
    }

    function test_allowanceSurvivesEmptyingAndRefillingBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(alice), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);

        vm.prank(bob);
        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        _assertConservation();
    }

    function test_directTransfersDoNotConsumeAllowance() public {
        assertTrue(token.transfer(alice, 3));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.prank(alice);
        assertTrue(token.transfer(spender, 1));
        assertEq(token.allowance(alice, spender), 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 2));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(bob), 2);
        _assertConservation();
    }

    function test_tokenContractReceivingTokensDoesNotBurnThem() public {
        assertTrue(token.transfer(address(token), SUPPLY - 1));
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(token), 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        _assertConservation();
    }

    function testFuzz_selfTransfersCannotBypassBalance(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount);
        vm.expectRevert(expected);
        vm.prank(alice);
        token.transfer(alice, amount);

        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(alice, alice, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        _assertConservation();
    }

    function testFuzz_splitDelegatedTransfersEqualSingleTransfer(uint256 amount, uint256 first, uint256 approved)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        approved = bound(approved, amount, type(uint256).max);
        Pimd single = new Pimd();
        assertTrue(single.approve(spender, approved));
        assertTrue(token.approve(spender, approved));

        vm.prank(spender);
        assertTrue(single.transferFrom(address(this), alice, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount - first));

        // A single payment and any partition of it must have the same observable effect.
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(single.totalSupply(), SUPPLY);
        _assertConservation();
    }

    function testFuzz_returningTokensDoesNotRestoreSpentAllowance(uint256 approved, uint256 first) public {
        approved = bound(approved, 1, SUPPLY);
        first = bound(first, 1, approved);
        assertTrue(token.transfer(alice, approved));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, first));
        assertEq(token.balanceOf(alice), approved - first);
        assertEq(token.balanceOf(bob), first);
        vm.prank(bob);
        assertTrue(token.transfer(alice, first));
        assertEq(token.balanceOf(alice), approved);
        assertEq(token.allowance(alice, spender), approved - first);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, approved - first));
        // The owner still has tokens, but the cumulative approval is exhausted.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), approved - first);
        assertEq(token.allowance(alice, spender), 0);
        _assertConservation();
    }

    function testFuzz_approvalReplacementIsIdempotentAndIsolated(uint256 first, uint256 last) public {
        assertTrue(token.transfer(alice, SUPPLY / 2));
        assertTrue(token.approve(spender, first));
        vm.prank(alice);
        assertTrue(token.approve(bob, first));
        vm.prank(alice);
        assertTrue(token.approve(spender, first));

        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Approval(alice, spender, last);
            vm.prank(alice);
            assertTrue(token.approve(spender, last));
            assertEq(token.allowance(alice, spender), last);
            assertEq(token.allowance(alice, bob), first);
            assertEq(token.allowance(address(this), spender), first);
            assertEq(token.balanceOf(alice), SUPPLY / 2);
            assertEq(token.balanceOf(address(this)), SUPPLY / 2);
        }
        _assertConservation();
    }

    function testFuzz_zeroRecipientFailurePreservesApproval(uint256 amount, uint256 approved) public {
        // Deliberately allow amounts above total supply: valid allowance must not bypass address validation.
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertConservation();
    }

    function testFuzz_failedSpendCanBeRetriedAfterFunding(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.transfer(alice, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        _assertConservation();
    }

    function _assertConservation() internal view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(spender)
                + token.balanceOf(address(token)),
            SUPPLY
        );
    }
}
