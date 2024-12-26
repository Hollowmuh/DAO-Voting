//  SPDX-License-Identifier: MIT
pragma solidity >0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
contract Voting is ReentrancyGuard, AccessControl{
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
    // Add session state management
    enum SessionState {
        Inactive, 
        Locking, 
        Voting, 
        Ended }



    struct Proposal {
        address author;
        uint256 id;
        uint256 creationTime;
        string name;
        uint256 acceptedVotes;
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
    IERC20 private tokenContract;
    //Mappings
    mapping(address => mapping(uint256 => Voter)) private voters;
    mapping(uint256 => VotingSession) public votingSessions;
    mapping(uint256 => Proposal) public activeProposals;
    mapping(address => uint256) private userProposalCount;
    mapping(uint256 => bool) private proposalInVoting;
    mapping(uint256 => uint256) private proposalQueue;
    mapping(address => uint256) private  totalLockedBalance;
    mapping(address => mapping (uint256 => bool)) public usersVoteStatus;
    Proposal[] public proposals;
    SessionState public sessionState;
    //Constants
    uint256 private constant VOTING_DURATION = 5 minutes;//3 days;
    uint256 private constant LOCKING_DURATION = 5 minutes;
    uint256 private constant MAX_ACTIVE_PROPOSAL = 5;
    uint256 private constant YEARLY_PROPOSAL_PER_USER = 5;
    uint256 private constant MIN_PERCENTAGE_LOCK = 10;
    uint256 private constant MAX_VOTE_WEIGHT = 10**4;
    uint256 private proposalIndex;
    uint256 private activeProposalIndex;
    uint256 private queueLength;
    uint256 private tokenSupply;
    uint256 private currentSessionId;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    //events
    event ProposalCreated(uint256 indexed proposalId, address indexed author, string name);
    event ProposalVoted(uint256 indexed proposalId, address indexed voter, VotingOptions voteOption);
    event ProposalClosed(uint256 indexed proposalId, Status status);
    event ProposalVoting(uint256 indexed proposalId, Status status);
    event SessionStarted(uint256 indexed sessionId, uint256 startTime, Proposal includedProposals);
    //event SessionEnded(uint256 indexed sessionId, uint256 endTIme, Proposal includedProposals);
    event TokensLocked(address indexed voter, uint256 sessionId, uint256 amount);
    event TokensUnlocked(address indexed voter, uint256 sessionId, uint256 amount);
    modifier onlyState(SessionState _state) {
    require(sessionState == _state, "Invalid session state");
    _;
    }


    
    constructor(address _tokenAddress) {
        tokenContract = IERC20(_tokenAddress);
        tokenSupply = tokenContract.totalSupply();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    function createProposal(string memory _name) external {
        address _proposee = msg.sender;
        require(bytes(_name).length > 0 && bytes(_name).length <= 200, "Invalid proposal name");
        require(userProposalCount[_proposee] < YEARLY_PROPOSAL_PER_USER, "User Creation Limit Reached");
        require(activeProposalIndex < MAX_ACTIVE_PROPOSAL, "Active Proposals Limit Reached");
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
        proposalQueue[queueLength] = _proposalId;
        proposalInVoting[_proposalId] = false;
        ++userProposalCount[msg.sender];
        emit ProposalCreated((_proposalId), msg.sender, _name);
        }
    function processPendingProposals() public {
        uint256 processedCount;
        uint256 nextProposal;
        require(activeProposalIndex < MAX_ACTIVE_PROPOSAL, "Max Active Proposal Reached");
        require(queueLength != 0, "No pending proposlas");
        for (; nextProposal <= MAX_ACTIVE_PROPOSAL; ++nextProposal) {
            uint256 proposalId = proposalQueue[nextProposal];
            if (!proposalInVoting[proposalId]) {
            Proposal storage activeProposal = proposals[proposalId];
            proposalInVoting[proposalId] = true;
    
            activeProposals[proposalId] = Proposal(
                activeProposal.author,
                activeProposalIndex,
                block.timestamp,
                activeProposal.name,
                activeProposal.acceptedVotes,
                activeProposal.rejectedVotes,
                Status.Proceeding
            );
            if (votingSessions[currentSessionId].isActive) {
                votingSessions[currentSessionId].includedProposals[proposalId] = activeProposals[proposalId];
            }
            proposals[proposalId].status = Status.Proceeding;
            //includedProposals[_proposalId] = activeProposal;
            ++activeProposalIndex;
            ++processedCount;
            --queueLength;
            }
        }
    }
    function vote(uint _activeProposalId, VotingOptions voteOption) external onlyState(SessionState.Voting){
        Proposal storage proposal = activeProposals[_activeProposalId];
        require(activeProposals[_activeProposalId].status == Status.Proceeding, "Proposal not in voting period.");
        VotingSession storage currentSession = votingSessions[currentSessionId];
        require(currentSession.isActive, "Session not Accepting Votes");        
        require(currentSession.includedProposals[_activeProposalId].author != address(0), "Proposal not in current Session");
        Voter memory voter = voters[msg.sender][currentSessionId];
        require(!usersVoteStatus[msg.sender][_activeProposalId], "Voted!");
        require(voter.lockedAmount != 0, "No Locked Tokens found");        
        require(block.timestamp < proposal.creationTime + VOTING_DURATION, "Voting Period is over");
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
        emit ProposalVoted(_activeProposalId, msg.sender, voteOption);
    }
    function closeProposal(uint256 _activeProposalId) public {
        Proposal memory proposal = activeProposals[_activeProposalId];
        require((proposal.status == Status.Proceeding), "Proposal not in Voting Period");
        require(block.timestamp > proposal.creationTime + VOTING_DURATION, "Voting still in progress");
        for (uint i = _activeProposalId; i < activeProposalIndex - 1; i++) {
            activeProposals[i] = activeProposals[i+1];
        }        
        proposals[_activeProposalId].status = proposalResults(_activeProposalId);
        activeProposalIndex--;
        emit ProposalClosed(_activeProposalId, proposals[_activeProposalId].status);
    }
    function proposalResults(uint256 _proposalId) public view returns(Status){
        Proposal memory proposal = proposals[_proposalId];
        //nedd to add if same votecount, what happens
        require(block.timestamp > proposal.creationTime + VOTING_DURATION, "Voting still in progress");
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
        for (uint i=0; i<userProposalCount[msg.sender]; ++i) {
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
    function lockTokensForVoting(uint256 _amount) external nonReentrant onlyState(SessionState.Locking){
        require(votingSessions[currentSessionId].isActive, "Session Not Active For Voting");
        require(_amount != 0, "Amount must be greater than 0");
        require(block.timestamp < votingSessions[currentSessionId].startTime + LOCKING_DURATION, "Session not acepting Token locks");
        uint256 userBalance = tokenContract.balanceOf(msg.sender);
        require(userBalance > _amount, "Insufficient Balance");
        Voter storage voter = voters[msg.sender][currentSessionId];
        uint256 minRequired = (userBalance * MIN_PERCENTAGE_LOCK) / 100;
        require(_amount > minRequired, "Min Lock 10% of token Balance");
        voter.lockedAmount = voter.lockedAmount + _amount;
        voter.lockedTime = block.timestamp;
        totalLockedBalance[msg.sender] += _amount;
        votingSessions[currentSessionId].totalBalance = votingSessions[currentSessionId].totalBalance + _amount;
        require(tokenContract.transferFrom(msg.sender, address(this), _amount), "Transfer Failed");
        

        emit TokensLocked(msg.sender, currentSessionId, _amount);

    }
    function getTotalLockedBalance() public view returns(uint _totalLockedBalance) {
        require(block.timestamp > votingSessions[currentSessionId].startTime + LOCKING_DURATION, "Locking Duration not over yet");
        _totalLockedBalance = votingSessions[currentSessionId].totalBalance;
    }
    function calculateWeight(address _member, uint256 _lockedAmount) public view returns (uint256 voteWeight) {
        Voter memory voter = voters[_member][currentSessionId];
        require(voter.lockedAmount != 0, "User has not Locked any TOken");
        uint256 totalLocked = votingSessions[currentSessionId].totalBalance;
        uint256 memberShare = (_lockedAmount * tokenSupply) / totalLocked;

        // Apply a non-linear weighting formula
        voteWeight = (memberShare * memberShare) / tokenSupply;

        // Scale the result
        voteWeight = (voteWeight * MAX_VOTE_WEIGHT) / tokenSupply;

        // Ensure minimum weight
        voteWeight = voteWeight > 1 ? voteWeight : 1;

        // Cap maximum weight
        voteWeight = voteWeight < 10000 ? voteWeight : 10000;
    }
    function unlockTokens() external nonReentrant onlyState(SessionState.Ended){
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
    function activateSession() public onlyRole(OPERATOR_ROLE){
        require(!votingSessions[currentSessionId].isActive, "Current Session still active");
        require(sessionState == SessionState.Inactive, "Session must be inactive");
        // Increment session ID first to avoid any potential issues with the zero session
        ++currentSessionId;
    
        // Create new session storage reference
        VotingSession storage newSession = votingSessions[currentSessionId];
    
        // Set the session parameters individually
        newSession.sessionId = currentSessionId;
        newSession.startTime = block.timestamp;
        newSession.endTime = block.timestamp + VOTING_DURATION + LOCKING_DURATION;
        newSession.isActive = true;
        newSession.totalBalance = 0;     
        sessionState = SessionState.Locking;
    }
    function startSession() public onlyState(SessionState.Locking){
        VotingSession storage newSession = votingSessions[currentSessionId];
        newSession.totalBalance = getTotalLockedBalance();
        // Process any pending proposals for this session
        processPendingProposals();

        emit SessionStarted(
        currentSessionId,
        newSession.startTime, 
        newSession.includedProposals[0] // Note: You might want to emit multiple proposals or modify this
        );
        sessionState = SessionState.Voting;

    }
    function endSession() public onlyState(SessionState.Voting) {
    require(block.timestamp > votingSessions[currentSessionId].endTime, "Session not yet finished");
    require(votingSessions[currentSessionId].isActive, "Session not Active");
    
    for (uint i = 0; i < activeProposalIndex; ++i) {
        Proposal memory proposal = proposals[activeProposalIndex - 1-i];
        if(block.timestamp >= proposal.creationTime + VOTING_DURATION + LOCKING_DURATION && 
           !proposalInVoting[proposal.id]) {
            closeProposal(proposal.id);
        }
    }
    votingSessions[currentSessionId].isActive = false;
    sessionState = SessionState.Ended;
    }
    function getSessionInfo(uint256 sessionId) external view returns (uint256 startTime,uint256 endTime,bool isActive,uint256 totalBalance) {
        require(sessionId > 0, "Invalid Session ID");
        VotingSession storage s = votingSessions[sessionId];
        return (s.startTime,s.endTime,s.isActive,s.totalBalance);
    }
}

//0x9396B453Fad71816cA9f152Ae785276a1D578492