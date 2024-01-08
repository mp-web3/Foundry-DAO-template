// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {Timelock} from "../src/Timelock.sol";
import {GovToken} from "../src/GovToken.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    Timelock timelock;
    GovToken govToken;

    address public constant OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public USER = makeAddr("user");

    uint256 public constant INITIAL_SUPPLY = 100 ether;
    uint256 public constant MIN_DELAY = 3600; // 1 hour delay
    uint256 public constant VOTING_DELAY = 1; // How many blocks needs to be validated before a vote is active (we set this as 1 block in MyGovernor.sol)
    uint256 public constant VOTING_PERIOD = 50400; // This is equivalent to 1week, see in MyGovernor.sol

    address[] proposers;
    address[] executors;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;


    function setUp() public {
        govToken = new GovToken(OWNER);
        vm.startPrank(OWNER);
        govToken.mint(OWNER, INITIAL_SUPPLY);
        govToken.delegate(OWNER);

        timelock = new Timelock(MIN_DELAY, proposers, executors, OWNER);
        governor = new MyGovernor(govToken, timelock);

        // Remove the owner from controller of timelock and give it to governor;
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        // Executor role to anybody by passing a 0 address
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        // 
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, OWNER);

        box = new Box();
        box.transferOwnership(address(timelock));
        
        vm.stopPrank();
    }

    /*
    function testCannotUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }
    */

    function testGovernanceUpdatesBox() public {
        // We are going to propose that Box updates store value to 888
        uint256 valueToStore = 888;
        string memory description = "store 1 in box";
        // use calldata to call any function https://github.com/Cyfrin/foundry-nft-f23/blob/main/src/sublesson/CallAnything.sol
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // Log balance of GovToken for OWNER before proposing
        uint256 ownerBalanceBefore = govToken.balanceOf(OWNER);
        console.log("Owner balance before proposing:", ownerBalanceBefore);

        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        console.log(proposalId);

        // View the state of the proposal
        console.log("State after proposal:", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1 );
        vm.roll(block.number + VOTING_DELAY + 1 );

        // Log balance of GovToken for OWNER after proposing (before voting)
        uint256 ownerBalanceAfter = govToken.balanceOf(OWNER);
        console.log("Owner balance after proposing:", ownerBalanceAfter);
        console.log("State after voting delay:", uint256(governor.state(proposalId)));

        // Log voting power at snapshot
        uint256 snapshot = governor.proposalSnapshot(proposalId);
        uint256 ownerVotingPowerAtSnapshot = govToken.getPastVotes(OWNER, snapshot -1);
        console.log("Owner voting power at snapshot:", ownerVotingPowerAtSnapshot);

        // 2. Vote
        string memory reason = "I like to vote";

        uint8 voteWay = 1; // 0: Against | 1: For | 2: Abstain (see enum VoteType in GovernorCountingSimple.sol)

        vm.prank(OWNER);
        governor.castVoteWithReason(proposalId, voteWay, reason);
        console.log("State after voting:", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

            // Check vote counts and quorum
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        uint256 quorumRequired = governor.quorum(block.number - 1);
        console.log("Votes For:", forVotes);
        console.log("Votes Against:", againstVotes);
        console.log("Votes Abstain:", abstainVotes);
        console.log("Quorum Required:", quorumRequired);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Check state after voting period
        console.log("State after voting period:", uint256(governor.state(proposalId)));

        // 3. Queue the TX before we can execute them
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 4. Execute

        governor.execute(targets, values, calldatas, descriptionHash);


        console.log("Box value: ", box.getNumber());
        assert(box.getNumber() == valueToStore);

    }
}


/*  
    ///////////////////////////////// PROPOSE ////////////////////////////////////
    Function: propose
    Contract: Governor.sol
    Interface: IGovernor.sol

    // FUNCTION

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual returns (uint256) {
        address proposer = _msgSender();

        // check description restriction
        if (!_isValidDescriptionForProposer(proposer, description)) {
            revert GovernorRestrictedProposer(proposer);
        }

        // check proposal threshold
        uint256 proposerVotes = getVotes(proposer, clock() - 1);
        uint256 votesThreshold = proposalThreshold();
        if (proposerVotes < votesThreshold) {
            revert GovernorInsufficientProposerVotes(proposer, proposerVotes, votesThreshold);
        }

        return _propose(targets, values, calldatas, description, proposer);
    }

    // INTERFACE

    interface IGovernor is IERC165, IERC6372 {
        function propose(
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) external returns (uint256 proposalId);
    }


    /////////////////////// PROPOSAL STATE /////////////////////////////
    Function: state
    Contract: Governor.sol
    Interface: IGovernor.sol

    // FUNCTION

    function state(uint256 proposalId) public view virtual returns (ProposalState) {
        // We read the struct fields into the stack at once so Solidity emits a single SLOAD
        ProposalCore storage proposal = _proposals[proposalId];
        bool proposalExecuted = proposal.executed;
        bool proposalCanceled = proposal.canceled;

        if (proposalExecuted) {
            return ProposalState.Executed;
        }

        if (proposalCanceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert GovernorNonexistentProposal(proposalId);
        }

        uint256 currentTimepoint = clock();

        if (snapshot >= currentTimepoint) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= currentTimepoint) {
            return ProposalState.Active;
        } else if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        } else if (proposalEta(proposalId) == 0) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Queued;
        }
    }

    // INTERFACE

    interface IGovernor is IERC165, IERC6372 {
        enum ProposalState {
            Pending,
            Active,
            Canceled,
            Defeated,
            Succeeded,
            Queued,
            Expired,
            Executed
        }

    ...
    }


    ////////////////////////////////////// VOTE ////////////////////////////////
    Contract: Governor.sol
    Functions: castVote, castVoteWithReason
    Interface: 
    Abstract: GovernorCountingSimple.sol
    enum: VoteType

    // CASTVOTE

    function castVote(uint256 proposalId, uint8 support) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    // CASTVOTEWITHREASON

    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    // VOTETYPE

    enum VoteType {
        Against,
        For,
        Abstain
    }

    
    /////////////////////////////////// QUEUE /////////////////////////////////////
    Abstract Contract: GovernorTimelockControl.sol
    Function: _queueOperations
 
    // _QUEUEOPERATIONS

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override returns (uint48) {
        uint256 delay = _timelock.getMinDelay();

        bytes32 salt = _timelockSalt(descriptionHash);
        _timelockIds[proposalId] = _timelock.hashOperationBatch(targets, values, calldatas, 0, salt);
        _timelock.scheduleBatch(targets, values, calldatas, 0, salt, delay);

        return SafeCast.toUint48(block.timestamp + delay);
    }

    /////////////////////// GET VOTES AGAINST, FOR, AND ABSTAINED OF A PROPOSAL /////////////////////////////////////
    Abstract Contract: GovernorCountingSimple.sol
    Function: proposalVotes


    function proposalVotes(
        uint256 proposalId
    ) public view virtual returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        return (proposalVote.againstVotes, proposalVote.forVotes, proposalVote.abstainVotes);
    }

*/