// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pimd} from "../src/Pimd.sol";

/// @dev A local deployment/transfer fixture; not an application contract for launch.
contract PimdFactoryFixture {
    function deploy(bytes32 salt) external returns (Pimd) {
        return new Pimd{salt: salt}();
    }

    function send(Pimd token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract PimdTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Pimd internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new Pimd();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "Pimd");
        assertEq(token.symbol(), "PIMD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMintEvent() public {
        vm.recordLogs();
        Pimd fresh = new Pimd();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_create2DeploymentMintsOnlyToTheFactory() public {
        PimdFactoryFixture factory = new PimdFactoryFixture();
        bytes32 salt = keccak256("Pimd deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Pimd).creationCode))
                    )
                )
            )
        );

        vm.prank(alice, bob);
        Pimd fresh = factory.deploy(salt);
        assertEq(address(fresh), predicted);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_launchDistributionAndSubsequentTransfersAreExact() public {
        PimdFactoryFixture factory = new PimdFactoryFixture();
        Pimd fresh = factory.deploy(keccak256("launch flow test"));
        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool custody fixture");
        address requester = makeAddr("requester fixture");
        uint256 swarm = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;

        assertTrue(factory.send(fresh, distributor, swarm));
        assertTrue(factory.send(fresh, pool, poolShare));
        assertTrue(factory.send(fresh, requester, SUPPLY - swarm - poolShare));
        assertEq(fresh.balanceOf(address(factory)), 0);
        assertEq(fresh.balanceOf(distributor), swarm);
        assertEq(fresh.balanceOf(pool), poolShare);
        assertEq(fresh.balanceOf(requester), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(fresh.transfer(alice, swarm));
        assertEq(fresh.balanceOf(distributor), 0);
        assertEq(fresh.balanceOf(alice), swarm);

        vm.prank(pool);
        assertTrue(fresh.transfer(bob, 123 ether));
        assertEq(fresh.balanceOf(bob), 123 ether);
        vm.prank(bob);
        assertTrue(fresh.transfer(pool, 123 ether));
        assertEq(fresh.balanceOf(pool), poolShare);
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_transferMovesExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
    }

    function test_transferOverBalanceRevertsWithoutChangingState() public {
        token.transfer(alice, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 5 ether + 1)
        );
        vm.prank(alice);
        token.transfer(bob, 5 ether + 1);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 50 ether);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalCanBeReplacedAndRevoked() public {
        token.approve(spender, 50 ether);
        token.approve(spender, 7 ether);
        assertEq(token.allowance(address(this), spender), 7 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_approveZeroOwnerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 1);
    }

    function test_allowancesAreIsolatedByOwnerAndSpender() public {
        token.approve(spender, 40 ether);
        token.approve(bob, 5 ether);
        vm.prank(alice);
        token.approve(spender, 3 ether);
        assertEq(token.allowance(address(this), spender), 40 ether);
        assertEq(token.allowance(address(this), bob), 5 ether);
        assertEq(token.allowance(alice, spender), 3 ether);
        assertEq(token.allowance(bob, spender), 0);
    }

    function test_transferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        token.approve(spender, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20 ether));
        assertEq(token.allowance(address(this), spender), 30 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.balanceOf(alice), 20 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromCanExhaustAllowance() public {
        token.approve(spender, 50 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 50 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 50 ether);
    }

    function test_transferFromInfiniteApprovalDoesNotDecreaseAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20 ether));
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 20 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    function test_transferFromInsufficientAllowanceRevertsWithoutChangingState() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10 ether, 10 ether + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 10 ether + 1);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromWithoutApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_deployerCannotSpendAnotherHoldersTokensWithoutApproval() public {
        token.transfer(alice, 50 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 50 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 50 ether));
        assertEq(token.balanceOf(bob), 50 ether);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 6 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToZeroRestoresAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroSourceRevertsEvenForZeroAmount() public {
        // OpenZeppelin validates the allowance owner before attempting the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferFromConsumesAllowanceWithoutMovingBalance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_noMintBurnAdminOrUpgradeEntryPoints() public {
        token.transfer(alice, 100 ether);
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[9] = abi.encodeWithSignature("initialize(address)", bob);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[11] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", bob, bytes(""));
        calls[12] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[13] = abi.encodeWithSignature("owner()");
        calls[14] = abi.encodeWithSignature("_mint(address,uint256)", bob, 1);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached an unexpected entry point");
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger reached an unexpected entry point");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100 ether);
            assertEq(token.balanceOf(bob), 0);
        }

        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_nativeCurrencyAndUnknownCallsRevert() public {
        vm.deal(address(this), 1 ether);
        (bool received,) = address(token).call{value: 1 ether}("");
        assertFalse(received);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferPreservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceAlwaysReverts(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        token.transfer(alice, balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approveAnyAmount(uint256 amount) public {
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferFromAccounting(uint256 approved, uint256 amount) public {
        token.approve(spender, approved);
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        uint256 expectedAllowance = approved == type(uint256).max ? approved : approved - amount;
        assertEq(token.allowance(address(this), spender), expectedAllowance);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromAboveAllowanceAlwaysReverts(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_transferFromAboveBalanceRestoresAllowance(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
