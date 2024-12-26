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
    struct VotingSession {
        uint256 sessionId;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        mapping(uint256 => Proposal) includedProposals;
        uint256 totalBalance;
    }
    struct Voter{
        uint256 lockedAmount;
        uint256 lockedTime;
    }
    //Interface
    IERC20 tokenContract;
    //Mappings
    mapping(address => mapping(uint256 => Voter)) private voters;
    mapping(uint256 => VotingSession) public votingSessions;
    mapping(uint256 => Proposal) public activeProposals;
    mapping(address => uint256) public userProposalCount;
    mapping(uint256 => uint256) private proposalCreationTimes;
    mapping(uint256 => bool) public proposalInVoting;
    mapping(uint256 => uint256) public proposalQueue;
    mapping(address => uint256) public totalLockedBalance;
    mapping(address => mapping (uint256 => bool)) public usersVoteStatus;
    Proposal[] public proposals;
    //Constants
    uint256 private constant votingDuration = 5 minutes;//3 days;
    uint256 private constant timeDurationforLocking = 5 minutes;
    uint8 private constant maxActiveProposal = 5;
    uint8 private constant maxYearlyProposalPerUser = 5;
    uint8 private constant minLockPercentage = 10;
    uint32 proposalDelay = 50 seconds;
    uint256 private constant maxVoteWeight = 10000;

    uint256 proposalIndex;
    uint256 activeProposalIndex;
    uint256 public queueLength;
    uint256 public tokenSupply;
    uint256 public currentSessionId;
    //events
    event proposalCreated(uint256 indexed proposalId, address indexed author, string name);
    event proposalVoted(uint256 indexed proposalId, address indexed voter, VotingOptions voteOption);
    event proposalClosed(uint256 indexed proposalId, Status status);
    event proposalVoting(uint256 indexed proposalId, Status status);
    event SessionStarted(uint256 indexed sessionId, uint256 startTime, Proposal includedProposals);
    event SessionEnded(uint256 indexed sessionId, uint256 endTIme, Proposal includedProposals);
    event TokensLocked(address indexed voter, uint256 sessionId, uint256 amount);
    event TokensUnlocked(address indexed voter, uint256 sessionId, uint256 amount);



    
    constructor(address _tokenAddress) {
        tokenContract = IERC20(_tokenAddress);
        tokenSupply = tokenContract.totalSupply();
    }
    function createProposal(string memory _name) external {
        address _proposee = msg.sender;
        require(userProposalCount[_proposee] < maxYearlyProposalPerUser, "User Creation Limit Reached");
        require(activeProposalIndex < maxActiveProposal, "Active Proposals Limit Reached");
        require(queueLength<5, "Max pending proposals reached");
        require(tokenContract.balanceOf(msg.sender) != 0, "No Token Balance");
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
        require(queueLength != 0, "No pending proposlas");
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
        proposalInVoting[_proposalId] = true;
    
        activeProposals[_proposalId] = Proposal(
            activeProposal.author,
            activeProposalIndex,
            block.timestamp,
            activeProposal.name,
            activeProposal.acceptedVotes,
            activeProposal.rejectedVotes,
            Status.Proceeding
        );
        if (votingSessions[currentSessionId].isActive) {
            votingSessions[currentSessionId].includedProposals[_proposalId] = activeProposals[_proposalId];
        }
        proposals[_proposalId].status = Status.Proceeding;
        //includedProposals[_proposalId] = activeProposal;
        activeProposalIndex++;
        
    }
    function vote(uint _activeProposalId, VotingOptions voteOption) external {
        Proposal storage proposal = activeProposals[_activeProposalId];
        require(activeProposals[_activeProposalId].status == Status.Proceeding, "Proposal not in voting period.");
        VotingSession storage currentSession = votingSessions[currentSessionId];
        require(currentSession.isActive == true, "Session not Accepting Votes");        
        require(currentSession.includedProposals[_activeProposalId].author != address(0), "Proposal not in current Session");
        Voter storage voter = voters[msg.sender][currentSessionId];
        require(!usersVoteStatus[msg.sender][_activeProposalId], "You have already Voted on this proposal");
        require(voter.lockedAmount != 0, "No Locked Tokens found");        
        require(block.timestamp < proposal.creationTime + votingDuration, "Voting Period is over");
        uint senderWeight = calculateWeight(msg.sender, voter.lockedAmount);
        if (voteOption == VotingOptions.Accept) {
            //YES
            proposal.acceptedVotes = proposal.acceptedVotes + senderWeight;
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
    function closeProposal(uint256 _activeProposalId) public {
        Proposal memory proposal = activeProposals[_activeProposalId];
        require((proposal.status == Status.Proceeding), "Proposal not in Voting Period");
        require(block.timestamp > proposal.creationTime + votingDuration, "Voting still in progress");
        delete activeProposals[_activeProposalId];
        proposals[_activeProposalId].status = proposalResults(_activeProposalId);
        activeProposalIndex--;
        emit proposalClosed(_activeProposalId, proposals[_activeProposalId].status);
    }
    function proposalResults(uint256 _proposalId) public view returns(Status status){
        Proposal memory proposal = proposals[_proposalId];
        //nedd to add if same votecount, what happens
        require(block.timestamp > proposal.creationTime + votingDuration, "Voting still in progress");
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
    function lockTokensForVoting(uint256 _amount) external {
        require(votingSessions[currentSessionId].isActive, "Session Not Active For Voting");
        require(_amount != 0, "Amount must be greater than 0");
        require(block.timestamp < votingSessions[currentSessionId].startTime + timeDurationforLocking, "Session not acepting Token locks");
        uint256 userBalance = tokenContract.balanceOf(msg.sender);
        require(userBalance > _amount, "Insufficient Balance");
        Voter storage voter = voters[msg.sender][currentSessionId];
        uint256 minRequired = (userBalance * minLockPercentage) / 100;
        require(_amount > minRequired, "Minimum Lock 10% of token Balance");
        require(tokenContract.transferFrom(msg.sender, address(this), _amount), "Transfer Failed");
        voter.lockedAmount = _amount;
        voter.lockedTime = block.timestamp;
        totalLockedBalance[msg.sender] += _amount;
        votingSessions[currentSessionId].totalBalance = votingSessions[currentSessionId].totalBalance + _amount;
        emit TokensLocked(msg.sender, currentSessionId, _amount);

    }
    function getTotalLockedBalance() public view returns(uint TotalLockedBalance) {
        require(block.timestamp > votingSessions[currentSessionId].startTime + timeDurationforLocking, "Locking Duration not over yet");
        TotalLockedBalance = votingSessions[currentSessionId].totalBalance;
    }
    function calculateWeight(address _member, uint256 _lockedAmount) public view returns (uint256 voteWeight) {
        Voter storage voter = voters[_member][currentSessionId];
        require(voter.lockedAmount != 0, "User has not Locked any TOken");
        uint256 totalLocked = votingSessions[currentSessionId].totalBalance;
        uint256 memberShare = (_lockedAmount * tokenSupply) / totalLocked;

        // Apply a non-linear weighting formula
        voteWeight = (memberShare * memberShare) / tokenSupply;

        // Scale the result
        voteWeight = (voteWeight * maxVoteWeight) / tokenSupply;

        // Ensure minimum weight
        voteWeight = voteWeight > 1 ? voteWeight : 1;

        // Cap maximum weight
        voteWeight = voteWeight < 10000 ? voteWeight : 10000;
    }
    function unlockTokens() external {
        VotingSession storage session = votingSessions[currentSessionId];
        require(!session.isActive || block.timestamp > session.endTime, "Session still active");
        Voter storage voter = voters[msg.sender][currentSessionId];
        require(voter.lockedAmount != 0, "No tokens to Unlock");
        uint256 amountToUnlock = voter.lockedAmount;
        voter.lockedAmount = 0;
        session.totalBalance -= amountToUnlock;
        totalLockedBalance[msg.sender] -= amountToUnlock;
        require(tokenContract.transfer(msg.sender, amountToUnlock), "Transer Failed");
        emit TokensUnlocked(msg.sender, currentSessionId, amountToUnlock);
    }
    function activateSession() public {
        // Increment session ID first to avoid any potential issues with the zero session
        ++currentSessionId;
    
        // Create new session storage reference
        VotingSession storage newSession = votingSessions[currentSessionId];
    
        // Set the session parameters individually
        newSession.sessionId = currentSessionId;
        newSession.startTime = block.timestamp;
        newSession.endTime = block.timestamp + votingDuration + timeDurationforLocking;
        newSession.isActive = true;
        newSession.totalBalance = 0;
    
    
    
    }
    function startSession() public {
        VotingSession storage newSession = votingSessions[currentSessionId];
        newSession.totalBalance = getTotalLockedBalance();
        // Process any pending proposals for this session
        processPendingProposals();

        emit SessionStarted(
        currentSessionId,
        newSession.startTime, 
        newSession.includedProposals[0] // Note: You might want to emit multiple proposals or modify this
        );

    }
    function endSession() public {
        require(block.timestamp > votingSessions[currentSessionId].endTime, "Session not yet finished.");
        require(votingSessions[currentSessionId].isActive, "Session not Active");
    
        for (uint i = 0; i<activeProposalIndex; ++i) {
            Proposal memory proposal = proposals[activeProposalIndex - 1-i];
                if(block.timestamp >= proposal.creationTime + votingDuration + timeDurationforLocking && !proposalInVoting[proposal.id]) {
                    closeProposal(proposal.id);
                }
        votingSessions[currentSessionId].isActive = false;
    }

}
}
//0x9396B453Fad71816cA9f152Ae785276a1D578492