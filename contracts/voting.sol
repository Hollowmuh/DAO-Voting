// SPDX-License-Identifier: MIT
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
    struct Voter {
        address delegate; //allows voter to give their voting right to another
        uint vote; //THis would ve sued to know the opinion of the voter against or in favour or mayve avstain
        uint weight;
        bool voted;
    }
    struct Proposal {
        address author; //shows the author of the proposal
        uint256 id;
        uint256 creationTime;
        bytes32 name; //max of 32 char
        uint256 acceptedVotes; //number of accepted votes
        uint256 rejectedVotes;
        Status status;
    }
    //Interface
    IERC20 tokenContract;
    //Mappings
    mapping(address => Voter) public voters;
    mapping(uint256 => Proposal) public activeProposals;
    mapping(address => uint256) private userProposalCount;
    mapping(uint256 => uint256) private proposalCreationTimes;
    mapping(uint256 => bool) private proposalInVoting;
    mapping(uint256 => uint256) public proposalQueue;
    Proposal[] public proposals;
    //Constants
    uint256 private constant votingDuration = 3 days;
    uint8 private constant maxActiveProposal = 5;
    uint8 private constant maxYearlyProposalPerUser = 5;
    uint32 proposalDelay = 300 seconds;
    uint256 proposalIndex;
    uint256 pendingProposalIndex;
    uint256 activeProposalIndex;
    uint256 proposalCreationTime;
    uint256 queueLength;
    //events
    event proposalCreated(uint256 indexed proposalId, address indexed author, bytes32 name);
    event proposalVoted(uint256 indexed proposalId, address indexed voter, VotingOptions voteOption);
    event proposalClosed(uint256 indexed proposalId, Status status);
    event proposalVoting(uint256 indexed proposalId, Status status);

    
    constructor(address _tokenAddress) {
        tokenContract = IERC20(_tokenAddress);
    }
    
    function weight(address _member)internal view returns (uint256) {        
        uint256 balance = tokenContract.balanceOf(_member);
        uint256 tokenSupply = tokenContract.totalSupply();
        require(balance > 0, "Zero Token Balance!");
        uint256 baseWeight = balance/tokenSupply * 1000;
        uint256 randomFactor = uint256(keccak256(abi.encodePacked(block.timestamp,
        baseWeight,
        block.number,
        balance,
        msg.sender,
        tx.origin))) % 100;
        uint256 voteWeight = baseWeight + randomFactor;
        return voteWeight;
    }
    function createProposal(bytes32 _name) external {
        address _proposee = msg.sender;
        require(userProposalCount[_proposee] < maxYearlyProposalPerUser, "User Reached Proposal Limit per year");
        require(activeProposalIndex < maxActiveProposal, "Limit of Active Proposals Reached");
        require(weight(_proposee) >= 50, "Member's shares not enough!");
        // tryna think of how to prevent one person from proposing too much, think of a way to limit that without incurring sybil attacks.
        uint256 _proposalId = ++proposalIndex;
        uint256 _pendingProposalId = ++pendingProposalIndex;
        proposals[_proposalId] = Proposal(
            msg.sender,
            _proposalId,
            block.timestamp,
            _name,
            0,
            0,
            Status.Pending
        );
        activeProposals[_pendingProposalId] = Proposal(
        msg.sender,
        _pendingProposalId,
        block.timestamp,
        _name,
        0,
        0,
        Status.Pending
    );
        proposalIndex++;
        pendingProposalIndex++;
        proposalCreationTimes[_proposalId] = block.timestamp;
        proposalQueue[queueLength++] = _proposalId;
        proposalInVoting[_proposalId] =false;
        emit proposalCreated((_proposalId), msg.sender, _name);
        }
    function processPendingProposals() internal {
        uint256 currentTime = block.timestamp;
        uint256 processedCount;
        uint256 nextProposal;
        require(activeProposalIndex < 5);
        for (; nextProposal < queueLength; nextProposal++) {
            uint256 proposalId = proposalQueue[nextProposal];
            if (currentTime >= proposalCreationTimes[proposalId] + proposalDelay && !proposalInVoting[proposalId]) {
                votingPeriod(proposalId);
                processedCount++;
                if (processedCount >= 5) {
                    break;
                }
            }
        }
    }
    function votingPeriod(uint256 _proposalId) internal {
        Proposal storage activeProposal = proposals[_proposalId];
        uint256 _activeId = ++activeProposalIndex;
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
        activeProposalIndex++;
        pendingProposalIndex-1;
        
    }
    function delegate(address _to) external {
        Voter storage sender = voters[msg.sender];
        Voter storage _delegate = voters[_to];
        require(sender.weight > 0, "No right to vote");
        require(!sender.voted, "You already voted, cannot delegate");
        require(msg.sender != _to, "You cannot delegate to yourself");
        require(_delegate.weight > 0, "Delegate has no right to vote");
        require(!voters[_to].voted, "Address has voted");
        while(voters[_to].delegate != address(0)){
            _to = voters[_to].delegate;
            require(_to != msg.sender, "Found loop in delegation!");
        }                
        sender.voted = true;
        sender.delegate = _to;
        _delegate.weight += sender.weight;
    }
    function vote(uint _activeProposalId, VotingOptions voteOption) external {
        Voter memory sender = voters[msg.sender];
        Proposal memory proposal = activeProposals[_activeProposalId];
        require(activeProposals[_activeProposalId].status == Status.Pending, "Proposal not Pending");
        require(block.timestamp < proposal.creationTime + votingDuration, "Voting Period is over");
        require(sender.weight >= 0,"You have no right to Vote!");
        require(!sender.voted, "Already Voted!");
        uint256 userWeight = weight(msg.sender);
        if (voteOption == VotingOptions.Accept) {
            //YES
            proposal.acceptedVotes += userWeight;
        } else {
            // NO
            proposal.rejectedVotes += userWeight;
        }
        sender.vote = _activeProposalId;
        sender.voted = true;
        emit proposalVoted(_activeProposalId, msg.sender, voteOption);
    }
    function closeProposal(uint256 _activeProposalId) external {
        Proposal memory proposal = activeProposals[_activeProposalId];
        require((proposal.status == Status.Pending), "Proposal not Pending");
        require(block.timestamp >= proposal.creationTime, "Voting still in progress");
        delete proposal;
        activeProposalIndex--;
        emit proposalClosed(_activeProposalId, proposal.status);
    }
    function proposalResults(uint256 _proposalId) public view returns(Status status){
        Proposal memory proposal = proposals[_proposalId];
        //nedd to add if same votecount, what happens
        require(block.timestamp >= proposal.creationTime, "Voting still in progress");
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
// SPDX-License-Identifier: MIT
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
    struct Voter {
        address delegate; //allows voter to give their voting right to another
        uint vote; //THis would ve sued to know the opinion of the voter against or in favour or mayve avstain
        uint weight;
        bool voted;
    }
    struct Proposal {
        address author; //shows the author of the proposal
        uint256 id;
        uint256 creationTime;
        bytes32 name; //max of 32 char
        uint256 acceptedVotes; //number of accepted votes
        uint256 rejectedVotes;
        Status status;
    }
    //Interface
    IERC20 tokenContract;
    //Mappings
    mapping(address => Voter) public voters;
    mapping(uint256 => Proposal) public activeProposals;
    mapping(address => uint256) private userProposalCount;
    mapping(uint256 => uint256) private proposalCreationTimes;
    mapping(uint256 => bool) private proposalInVoting;
    mapping(uint256 => uint256) public proposalQueue;
    Proposal[] public proposals;
    //Constants
    uint256 private constant votingDuration = 3 days;
    uint8 private constant maxActiveProposal = 5;
    uint8 private constant maxYearlyProposalPerUser = 5;
    uint32 proposalDelay = 300 seconds;
    uint256 proposalIndex;
    uint256 pendingProposalIndex;
    uint256 activeProposalIndex;
    uint256 proposalCreationTime;
    uint256 queueLength;
    //events
    event proposalCreated(uint256 indexed proposalId, address indexed author, bytes32 name);
    event proposalVoted(uint256 indexed proposalId, address indexed voter, VotingOptions voteOption);
    event proposalClosed(uint256 indexed proposalId, Status status);
    event proposalVoting(uint256 indexed proposalId, Status status);

    
    constructor(address _tokenAddress) {
        tokenContract = IERC20(_tokenAddress);
    }
    
    function weight(address _member)internal view returns (uint256 voteWeight) {        
        uint256 balance = tokenContract.balanceOf(_member);
        uint256 tokenSupply = tokenContract.totalSupply();
        require(balance > 0, "Zero Token Balance!");
        uint256 baseWeight = balance/tokenSupply * 1000;
        uint256 randomFactor = uint256(keccak256(abi.encodePacked(block.timestamp,
        baseWeight,
        block.number,
        balance,
        msg.sender,
        tx.origin))) % 1000;
        voteWeight = baseWeight + randomFactor;
    }
    function createProposal(bytes32 _name) external {
        address _proposee = msg.sender;
        require(userProposalCount[_proposee] < maxYearlyProposalPerUser, "User Reached Proposal Limit per year");
        require(activeProposalIndex < maxActiveProposal, "Limit of Active Proposals Reached");
        require(weight(_proposee) >= 50, "Member's shares not enough!");
        // tryna think of how to prevent one person from proposing too much, think of a way to limit that without incurring sybil attacks.
        uint256 _proposalId = ++proposalIndex;
        uint256 _pendingProposalId = ++pendingProposalIndex;
        proposals[_proposalId] = Proposal(
            msg.sender,
            _proposalId,
            block.timestamp,
            _name,
            0,
            0,
            Status.Pending
        );
        activeProposals[_pendingProposalId] = Proposal(
        msg.sender,
        _pendingProposalId,
        block.timestamp,
        _name,
        0,
        0,
        Status.Pending
        );
        proposalIndex++;
        pendingProposalIndex++;
        proposalCreationTimes[_proposalId] = block.timestamp;
        proposalQueue[queueLength++] = _proposalId;
        proposalInVoting[_proposalId] =false;
        emit proposalCreated((_proposalId), msg.sender, _name);
        processPendingProposals();
        }
    function processPendingProposals() internal {
        uint256 currentTime = block.timestamp;
        uint256 processedCount;
        uint256 nextProposal;
        require(activeProposalIndex < 5);
        for (; nextProposal < queueLength; nextProposal++) {
            uint256 proposalId = proposalQueue[nextProposal];
            if (currentTime >= proposalCreationTimes[proposalId] + proposalDelay && !proposalInVoting[proposalId]) {
                votingPeriod(proposalId);
                processedCount++;
                if (processedCount >= 5) {
                    break;
                }
            }
        }
    }
    function votingPeriod(uint256 _proposalId) internal {
        Proposal storage activeProposal = proposals[_proposalId];
        uint256 _activeId = ++activeProposalIndex;
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
        activeProposalIndex++;
        pendingProposalIndex-1;
        
    }
    function delegate(address _to) external {
        Voter storage sender = voters[msg.sender];
        Voter storage _delegate = voters[_to];
        require(sender.weight > 0, "No right to vote");
        require(!sender.voted, "You already voted, cannot delegate");
        require(msg.sender != _to, "You cannot delegate to yourself");
        require(_delegate.weight > 0, "Delegate has no right to vote");
        require(!voters[_to].voted, "Address has voted");
        while(voters[_to].delegate != address(0)){
            _to = voters[_to].delegate;
            require(_to != msg.sender, "Found loop in delegation!");
        }                
        sender.voted = true;
        sender.delegate = _to;
        _delegate.weight += sender.weight;
    }
    function vote(uint _activeProposalId, VotingOptions voteOption) external {
        Voter memory sender = voters[msg.sender];
        Proposal memory proposal = activeProposals[_activeProposalId];
        require(activeProposals[_activeProposalId].status == Status.Pending, "Proposal not Pending");
        require(block.timestamp < proposal.creationTime + votingDuration, "Voting Period is over");
        require(sender.weight >= 0,"You have no right to Vote!");
        require(!sender.voted, "Already Voted!");
        uint256 userWeight = weight(msg.sender);
        if (voteOption == VotingOptions.Accept) {
            //YES
            proposal.acceptedVotes += userWeight;
        } else {
            // NO
            proposal.rejectedVotes += userWeight;
        }
        sender.vote = _activeProposalId;
        sender.voted = true;
        emit proposalVoted(_activeProposalId, msg.sender, voteOption);
    }
    function closeProposal(uint256 _activeProposalId) external {
        Proposal memory proposal = activeProposals[_activeProposalId];
        require((proposal.status == Status.Pending), "Proposal not Pending");
        require(block.timestamp >= proposal.creationTime, "Voting still in progress");
        delete proposal;
        activeProposalIndex--;
        emit proposalClosed(_activeProposalId, proposal.status);
    }
    function proposalResults(uint256 _proposalId) public view returns(Status status){
        Proposal memory proposal = proposals[_proposalId];
        //nedd to add if same votecount, what happens
        require(block.timestamp >= proposal.creationTime, "Voting still in progress");
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
