// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {VRFCoordinatorV2_5Mock} from "chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
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
        bytes32 requestId = entries[1].topics[1];
        // Assert
        assert(uint256(subId) == subscriptionId);
        assert(uint256(requestId) > 0);
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
    }

    /**
     * Fulfill random words test
     */
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public skipFork {
        // Arrange/Act/Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerAndResetsRaffle()
        public
        skipFork
    {
        // Arrange
        uint256 totalEntrants = 4;
        uint256 startingIndex = 1;

        for (
            uint256 i = startingIndex;
            i < startingIndex + totalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Pretend to be Chainlink VRF Coordinator
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address winner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = winner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * totalEntrants;

        assert(raffleState == Raffle.RaffleState.OPEN);
        assert(address(raffle).balance == 0);
        assert(winnerBalance == prize - entranceFee + 1 ether); // Winner gets back their entrance fee plus the prize
        assert(endingTimeStamp > 0);
    }
}
