// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "hardhat/console.sol";

error Raffle__FundingContractFailed();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);
error Raffle__CharityTransferFailed(address charity);
error Raffle__SendMoreToEnterRaffle();
error Raffle__RaffleNotOpen();
error Raffle__RaffleNotClosed();
error Raffle__JackpotTransferFailed();
error Raffle__MustBeFunder();
error Raffle__FundingToMatchTransferFailed();
error Raffle__DonationMatchFailed();

/**@title A sample Charity Raffle Contract originally @author Patrick Collins
 * @notice This contract creates a lottery in which players enter by donating to 1 of 3 charities
 * @dev This implements the Chainlink VRF Version 2
 */

contract CharityRaffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING,
        CLOSED
    }
    /* State variables */
    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 4;
    uint32 private immutable i_callbackGasLimit;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;

    // Lottery Variables
    uint256 private immutable i_duration;
    uint256 private immutable i_startTime;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_jackpot;
    uint256 private s_highestDonations;
    address private s_recentWinner;
    address private immutable i_charity1;
    address private immutable i_charity2;
    address private immutable i_charity3;
    address private immutable i_fundingWallet;
    address private s_charityWinner;
    bool private s_matchFunded;

    address[] private s_players;
    RaffleState private s_raffleState;

    mapping(address => uint256) donations;

    /* Events */
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);
    event CharityWinnerPicked(address indexed charity);

    /* Functions */
    constructor(
        address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint256 entranceFee,
        uint256 jackpot,
        uint256 duration,
        uint32 callbackGasLimit,
        address charity1,
        address charity2,
        address charity3,
        address fundingWallet
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_duration = duration;
        i_startTime = block.timestamp;
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_entranceFee = entranceFee;
        i_jackpot = jackpot;
        s_raffleState = RaffleState.OPEN;
        i_callbackGasLimit = callbackGasLimit;
        i_charity1 = charity1;
        i_charity2 = charity2;
        i_charity3 = charity3;
        i_fundingWallet = fundingWallet;
        (bool success, ) = payable(address(this)).call{value: jackpot}("");
        if (!success) {
            revert Raffle__FundingContractFailed();
        }
    }

    function enterRaffle(uint256 charityChoice) public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        if (charityChoice == 1) {
            (bool success, ) = i_charity1.call{value: msg.value}("");
            if (!success) {
                revert Raffle__CharityTransferFailed(i_charity1);
            }
            donations[i_charity1]++;
        }
        if (charityChoice == 2) {
            (bool success, ) = i_charity2.call{value: msg.value}("");
            if (!success) {
                revert Raffle__CharityTransferFailed(i_charity2);
            }
            donations[i_charity2]++;
        }
        if (charityChoice == 3) {
            (bool success, ) = i_charity3.call{value: msg.value}("");
            if (!success) {
                revert Raffle__CharityTransferFailed(i_charity3);
            }
            donations[i_charity3]++;
        }
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    /*
     * This is the function that the Chainlink Keeper nodes call
     * they look for `upkeepNeeded` to return True.
     * the following should be true for this to return true:
     * 1. The lottery is open.
     * 2. Lottery duration time has elapsed
     * 3. The contract has ETH.
     * 4. Implicity, your subscription is funded with LINK.
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timeOver = (block.timestamp - i_startTime) >= i_duration;
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timeOver && hasBalance && hasPlayers);
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256,
        /* requestId */
        uint256[] memory randomWords
    ) internal override {
        // declare player winner
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_players = new address[](0);
        s_raffleState = RaffleState.CLOSED;
        (bool success, ) = payable(recentWinner).call{value: address(this).balance}(""); // should be i_jackpot
        if (!success) {
            revert Raffle__JackpotTransferFailed();
        }
        // handle if there is charity donations tie
        bool tie = checkForTie();
        uint256 charity1Total = donations[i_charity1];
        donations[i_charity1] = 0;
        uint256 charity2Total = donations[i_charity2];
        donations[i_charity2] = 0;
        uint256 charity3Total = donations[i_charity3];
        donations[i_charity3] = 0;
        if (tie) {
            handleTie(randomWords, charity1Total, charity2Total, charity3Total);
        } else {
            // not a tie
            if (charity1Total > charity2Total && charity1Total > charity3Total) {
                // charity1 wins
                s_highestDonations = charity1Total;
                s_charityWinner = i_charity1;
                emit CharityWinnerPicked(i_charity1);
            }
            if (charity2Total > charity1Total && charity2Total > charity3Total) {
                // charity2 wins
                s_highestDonations = charity2Total;
                s_charityWinner = i_charity2;
                emit CharityWinnerPicked(i_charity2);
            }
            if (charity3Total > charity1Total && charity3Total > charity2Total) {
                // charity3 wins
                s_highestDonations = charity3Total;
                s_charityWinner = i_charity3;
                emit CharityWinnerPicked(i_charity3);
            }
        }
        emit WinnerPicked(recentWinner);
    }

    function checkForTie() internal view returns (bool) {
        if (
            donations[i_charity1] == donations[i_charity2] ||
            donations[i_charity1] == donations[i_charity3] ||
            donations[i_charity2] == donations[i_charity3]
        ) {
            return true;
        }
    }

    /*
     * @dev Instead of requesting 4 random words from Chainlink VRF, could get "sudo" random numbers by taking the hash and abi.encode of one random number (would be more computationally expensive function)
     */

    function handleTie(
        uint256[] memory randomWords,
        uint256 charity1Total,
        uint256 charity2Total,
        uint256 charity3Total
    ) internal {
        // find top two winners
        uint256[] memory data = new uint256[](3);
        data[0] = charity1Total;
        data[1] = charity2Total;
        data[2] = charity3Total;
        uint256[] memory sortedData = sort(data); // sortedData[2] = highest value
        s_highestDonations = sortedData[2];
        // three-way-tie
        if (charity1Total == charity2Total && charity1Total == charity3Total) {
            charity1Total += randomWords[1];
            charity2Total += randomWords[2];
            charity3Total += randomWords[3];
            uint256[] memory newData = new uint256[](3);
            newData[0] = charity1Total;
            newData[1] = charity2Total;
            newData[2] = charity3Total;
            uint256[] memory newSortedData = sort(newData);
            if (newSortedData[2] == charity1Total) {
                // charity1 wins
                s_charityWinner = i_charity1;
                emit CharityWinnerPicked(i_charity1);
            }
            if (newSortedData[2] == charity2Total) {
                //charity2 wins
                s_charityWinner = i_charity2;
                emit CharityWinnerPicked(i_charity2);
            } else {
                // charity3 wins
                s_charityWinner = i_charity3;
                emit CharityWinnerPicked(i_charity3);
            }
        }
        // charity1 and charity2 tie
        if (sortedData[2] == charity1Total && sortedData[2] == charity2Total) {
            charity1Total += randomWords[1];
            charity2Total += randomWords[2];
            if (charity1Total > charity2Total) {
                // charity1 wins
                s_charityWinner = i_charity1;
                emit CharityWinnerPicked(i_charity1);
            } else {
                //charity2 wins
                s_charityWinner = i_charity2;
                emit CharityWinnerPicked(i_charity2);
            }
        }
        // charity1 and charity3 tie
        if (sortedData[2] == charity1Total && sortedData[2] == charity3Total) {
            charity1Total += randomWords[1];
            charity3Total += randomWords[2];
            if (charity1Total > charity3Total) {
                // charity1 wins
                s_charityWinner = i_charity1;
                emit CharityWinnerPicked(i_charity1);
            } else {
                //charity3 wins
                s_charityWinner = i_charity3;
                emit CharityWinnerPicked(i_charity3);
            }
        }
        // charity2 and charity3 tie
        if (sortedData[2] == charity2Total && sortedData[2] == charity3Total) {
            charity2Total += randomWords[1];
            charity3Total += randomWords[2];
            if (charity2Total > charity3Total) {
                // charity2 wins
                s_charityWinner = i_charity2;
                emit CharityWinnerPicked(i_charity2);
            } else {
                //charity3 wins
                s_charityWinner = i_charity3;
                emit CharityWinnerPicked(i_charity3);
            }
        }
    }

    function sort(uint256[] memory data) internal returns (uint256[] memory) {
        quickSort(data, int256(0), int256(data.length - 1));
        return data;
    }

    function quickSort(
        uint256[] memory arr,
        int256 left,
        int256 right
    ) internal {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) quickSort(arr, left, j);
        if (i < right) quickSort(arr, i, right);
    }

    function fundDonationMatch() external {
        if (s_raffleState != RaffleState.CLOSED) {
            revert Raffle__RaffleNotClosed();
        }
        if (msg.sender != i_fundingWallet) {
            revert Raffle__MustBeFunder();
        }
        uint256 mostDonations = s_highestDonations;
        s_highestDonations = 0;
        (bool fundingSuccess, ) = payable(address(this)).call{value: mostDonations * i_entranceFee}("");
        if (!fundingSuccess) {
            revert Raffle__FundingToMatchTransferFailed();
        }
        s_matchFunded = true;
    }

    function DonationMatch() external {
        if (s_raffleState != RaffleState.CLOSED) {
            revert Raffle__RaffleNotClosed();
        }
        if (msg.sender != i_fundingWallet) {
            revert Raffle__MustBeFunder();
        }
        if (!s_matchFunded) {
            revert Raffle__FundingToMatchTransferFailed();
        }
        address charityWinner = s_charityWinner;
        s_charityWinner = address(0);
        s_matchFunded = false;
        (bool donationMatch, ) = payable(charityWinner).call{value: address(this).balance}("");
        if (!donationMatch) {
            revert Raffle__DonationMatchFailed();
        }
    }

    /** Getter Functions */

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() external pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() external pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getCharityWinner() external view returns (address) {
        return s_charityWinner;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getAllPlayers() external view returns (address[] memory) {
        return s_players;
    }

    function getCharities() external view returns (address[] memory charities) {
        charities[0] = i_charity1;
        charities[1] = i_charity2;
        charities[2] = i_charity3;
    }

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getFundingWallet() external view returns (address) {
        return i_fundingWallet;
    }

    function getHighestDonations() external view returns (uint256) {
        return s_highestDonations;
    }

    function getJackpot() external view returns (uint256) {
        return i_jackpot;
    }

    function getDuration() external view returns (uint256) {
        return i_duration;
    }
}