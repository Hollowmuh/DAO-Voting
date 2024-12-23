//  SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract Voting {
    // this one does a seperate proposal for each option.
    enum VotingOptions{
        Accept,
        Reject
    }
    enum Status{
        Accepted,
        Rejected,
        Indecisive,
        Pending,
        Proceeding
    }
    struct Proposal {
        address author; //shows the author of the proposal
        uint256 id;
        uint256 creationTime;
        string name; //max of 32 char
        uint256 acceptedVotes; //number of accepted votes
        uint256 rejectedVotes;
        Status status;
    }
    //Interface
    IERC20 tokenContract;
    //Mappings
    mapping(uint256 => Proposal) public activeProposals;
    mapping(address => uint256) public userProposalCount;
    mapping(uint256 => uint256) private proposalCreationTimes;
    mapping(uint256 => bool) public proposalInVoting;
    mapping(uint256 => uint256) public proposalQueue;
    mapping(address => mapping (uint256 => bool)) public usersVoteStatus;
    Proposal[] public proposals;
    //Constants
    uint256 private constant votingDuration = 2 minutes;//3 days;
    uint8 private constant maxActiveProposal = 5;
    uint8 private constant maxYearlyProposalPerUser = 5;
    uint32 proposalDelay = 50 seconds;
    uint256 proposalIndex;
    uint256 activeProposalIndex;
    uint256 proposalCreationTime;
    uint256 public queueLength;
    uint256 public tokenSupply;
    //events
    event proposalCreated(uint256 indexed proposalId, address indexed author, string name);
    event proposalVoted(uint256 indexed proposalId, address indexed voter, VotingOptions voteOption);
    event proposalClosed(uint256 indexed proposalId, Status status);
    event proposalVoting(uint256 indexed proposalId, Status status);

    
    constructor(address _tokenAddress) {
        tokenContract = IERC20(_tokenAddress);
        tokenSupply = tokenContract.totalSupply();
    }
    
    function weight(address _member) public view returns (uint256 voteWeight) {
        uint256 balance = tokenContract.balanceOf(_member);
        require(balance > 0, "Zero Token Balance!");
        uint256 baseWeight;
        // Calculate the base weight (e.g., 100 tokens = 1 unit of weight)
        if (tokenSupply <  10000) {
            baseWeight = 500;
        } else if (tokenSupply > 10000 && tokenSupply < 100000) {
            baseWeight = 5000;
        }else if (tokenSupply > 100000 && tokenSupply < 10000000) {
            baseWeight = 50000;
        }else if (tokenSupply > 10000000 && tokenSupply < 1000000000) {
            baseWeight = 500000;
        }else if (tokenSupply > 1000000000 && tokenSupply < 100000000000) {
            baseWeight = 5000000;
        }else if (tokenSupply > 100000000000 && tokenSupply < 10000000000000) {
            baseWeight = 50000000;
        }else {
            baseWeight = 5000000000;
        }    
        voteWeight = (baseWeight * balance)/ tokenSupply;    
        // Ensure minimum weight for small balances
        voteWeight = voteWeight > 1 ? voteWeight : 1;
    }
    function createProposal(string memory _name) external {
        address _proposee = msg.sender;
        require(userProposalCount[_proposee] < maxYearlyProposalPerUser, "User Reached Proposal Limit per year");
        require(activeProposalIndex < maxActiveProposal, "Limit of Active Proposals Reached");
        require(queueLength<5, "Maximum pending proposals reached");
        // tryna think of how to prevent one person from proposing too much, think of a way to limit that  without incurring sybil attacks.
        uint256 _proposalId = proposalIndex;
        proposals.push(Proposal(
            msg.sender,
            _proposalId,
            block.timestamp,
            _name,
            0,
            0,
            Status.Pending
        ));
        proposalIndex++;
        queueLength++;
        proposalCreationTimes[_proposalId] = block.timestamp;
        proposalQueue[queueLength] = _proposalId;
        proposalInVoting[_proposalId] =false;
        userProposalCount[msg.sender]++;
        emit proposalCreated((_proposalId), msg.sender, _name);
        }
    function processPendingProposals() public {
        uint256 currentTime = block.timestamp;
        uint256 processedCount;
        uint256 nextProposal;
        require(activeProposalIndex < maxActiveProposal);
        for (; nextProposal <= maxActiveProposal; nextProposal++) {
            uint256 proposalId = proposalQueue[nextProposal];
            if (currentTime >= proposalCreationTimes[proposalId] + proposalDelay && !proposalInVoting[proposalId]) {
                votingPeriod(proposalId);
                processedCount++;
                queueLength--;
            }
        }
    }
    function votingPeriod(uint256 _proposalId) internal {
        Proposal storage activeProposal = proposals[_proposalId];
        uint256 _activeId = activeProposalIndex;
        proposalInVoting[_proposalId] = true;
    
        activeProposals[_proposalId] = Proposal(
            activeProposal.author,
            _activeId,
            block.timestamp,
            activeProposal.name,
            activeProposal.acceptedVotes,
            activeProposal.rejectedVotes,
            Status.Proceeding
        );
        proposals[_proposalId].status = Status.Proceeding;
        activeProposalIndex++;
        
    }
    function vote(uint _activeProposalId, VotingOptions voteOption) external {
        Proposal storage proposal = activeProposals[_activeProposalId];
        require(!usersVoteStatus[msg.sender][_activeProposalId], "You have already Voted");
        require(activeProposals[_activeProposalId].status == Status.Proceeding, "Proposal not in voting period.");
        require(block.timestamp < proposal.creationTime + votingDuration, "Voting Period is over");
        uint senderWeight = weight(msg.sender);
        if (voteOption == VotingOptions.Accept) {
            //YES
            proposal.acceptedVotes += senderWeight;
            proposals[_activeProposalId].acceptedVotes += senderWeight;
            usersVoteStatus[msg.sender][_activeProposalId] = true;
        } else {
            // NO
            proposal.rejectedVotes += senderWeight;
            proposals[_activeProposalId].rejectedVotes += senderWeight;
            usersVoteStatus[msg.sender][_activeProposalId] = true;
        }
        emit proposalVoted(_activeProposalId, msg.sender, voteOption);
    }
    function closeProposal(uint256 _activeProposalId) external {
        Proposal memory proposal = activeProposals[_activeProposalId];
        require((proposal.status == Status.Proceeding), "Proposal not in Voting Period");
        require(block.timestamp >= proposal.creationTime + votingDuration, "Voting still in progress");
        delete activeProposals[_activeProposalId];
        proposals[_activeProposalId].status = proposalResults(_activeProposalId);
        activeProposalIndex--;
        emit proposalClosed(_activeProposalId, proposals[_activeProposalId].status);
    }
    function proposalResults(uint256 _proposalId) public view returns(Status status){
        Proposal memory proposal = proposals[_proposalId];
        //nedd to add if same votecount, what happens
        require(block.timestamp >= proposal.creationTime + votingDuration, "Voting still in progress");
        if (proposal.acceptedVotes > proposal.rejectedVotes) {
            proposal.status = Status.Accepted;
        }else if (proposal.rejectedVotes > proposal.acceptedVotes) {
            proposal.status = Status.Rejected;            
        } else {
            proposal.status = Status.Indecisive;
        }
        return proposal.status;        
        }              
    function getUserProposals() external view returns(Proposal[] memory userProposals) {
        userProposals = new Proposal[](userProposalCount[msg.sender]);
        for (uint i=0; i<userProposalCount[msg.sender]; i++) {
            uint256 userProposalId = proposals[userProposalCount[msg.sender] - 1-i].id;
            Proposal memory userProposal = proposals[userProposalId];
            userProposals[i] = Proposal(
                userProposal.author,
                userProposal.id,
                userProposal.creationTime,
                userProposal.name,
                userProposal.acceptedVotes,
                userProposal.rejectedVotes,
                userProposal.status
            );
        }
    }
    
}