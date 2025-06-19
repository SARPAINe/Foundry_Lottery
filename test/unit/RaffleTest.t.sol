// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    address public PLAYER_1 = makeAddr("PLAYER_1");
    uint256 public constant STARTING_PLAYERS_BALANCE = 10 ether;

    event EnteredRaffle(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
        console.log("subscriptionid inside console:", subscriptionId);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /**
     * @dev This test checks that the enterRaffle function reverts if the player sends less than the entrance fee.
     */
    function testEnterRaffleRevertsIfNotEnoughEth() public {
        // Arrange
        vm.prank(PLAYER_1);
        //Act / Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    /**
     * @dev This test checks that the enterRaffle function appends the player to the players array
     */
    function testEnterRaffleAddsPlayerToArray() public {
        // Arrange
        vm.prank(PLAYER_1);
        vm.deal(PLAYER_1, STARTING_PLAYERS_BALANCE);

        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        address payable[] memory players = raffle.getPlayers();
        assertEq(players[0], PLAYER_1);
    }

    /**
     * @dev This test checks that the enterRaffle function emits the EnteredRaffle event
     */
    function testEnteringRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER_1);
        vm.deal(PLAYER_1, STARTING_PLAYERS_BALANCE);

        // Act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER_1);

        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER_1);
        vm.deal(PLAYER_1, STARTING_PLAYERS_BALANCE);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Assert
        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfNotEnoughEth() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        //arrange
        vm.prank(PLAYER_1);
        vm.deal(PLAYER_1, STARTING_PLAYERS_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(upkeepNeeded == false);
    }

    function testPerformUpkeepCanOnlyBeCalledIfCheckUpkeepReturnsTrue() public {
        // Arrange
        vm.prank(PLAYER_1);
        vm.deal(PLAYER_1, STARTING_PLAYERS_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act/Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepReturnsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.prank(PLAYER_1);
        vm.deal(PLAYER_1, STARTING_PLAYERS_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = address(raffle).balance;
        numPlayers = raffle.getPlayers().length;

        // Act/Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                numPlayers,
                currentBalance,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {
        // Arrange
        vm.prank(PLAYER_1);
        vm.deal(PLAYER_1, STARTING_PLAYERS_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 subId = entries[0].topics[2];
        // Assert
        // console.log("SubId:", subId);
        console.log("SubscriptionId:", subscriptionId);
        console.log("SubId:", uint256(subId));
        assert(uint256(subId) == subscriptionId);
    }
}
