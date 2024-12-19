-// SPDX-License-Identifier: MIT
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
        Pending
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
    mapping(address => Voter) public voters;
    mapping(uint256 => Proposal) public activeProposals;
    mapping(address => uint256) private userProposalCount;
    Proposal[] public proposals;
    uint8 private constant votingDuration = 3 days;
    uint8 private constant maxActiveProposal = 5;
    uint8 private constant maxYearlyProposalPerUser = 5;
    uint8 private constant proposalDuration = 360 days;
    uint256 proposalIndex;
    uint256 activeProposalIndex;
    event proposalCreated(uint256 indexed proposalId, address indexed author, bytes32 name);
    event proposalVoted(uint256 indexed proposalId, address indexed voter, uint256 voteOption);
    event proposalClosed(uint256 indexed proposalId, Status status);
    event proposalResult(uint256 indexed proposalId, Status status);

    
    constructor(address _tokenAddress) {
        tokenContract = IERC20(_tokenAddress);
    }
    IERC20 tokenContract;
    function weight(address _member)internal view returns (uint256) {        
        uint256 balance = tokenContract.balanceOf(_member);
        uint256 voteWeight = balance.div(1000).add(balance.mod(1000)).div(1);
        return voteWeight;
    }
    function createProposal(bytes32 _name) external {
        address _proposee = msg.sender;
        require(userProposalCount[_proposee] < maxYearlyProposalPerUser, "User Reached Proposal Limit per year");
        require(activeProposals.length < maxActiveProposal, "Limit of Active Proposals Reached");
        require(weight(_proposee) >= 1000, "Member's shares not enough!");
        // tryna think of how to prevent one person from proposing too much, think of a way to limit that without incurring sybil attacks.
        uint256 _proposalId = ++proposalIndex;
        uint256 _activeProposalId = ++activeProposalIndex;
        proposals[_proposalId] = Proposal(
            msg.sender,
            _proposalId,
            block.timestamp,
            _name,
            0,
            0,
            Status.Pending
        );
        proposalIndex++;
        activeProposals[_activeProposalId] = Proposal(
            msg.sender,
            _activeProposalId,
            block.timestamp,
            _name,
            0,
            0,
            Status.Pending
        );
        activeProposalIndex++;
        emit proposalCreated((_proposalId), msg.sender, _name);
    }
    function delegate(address _to) external {
        Voter storage sender = voters[msg.sender];
        require(sender.weight > 0, "No right to vote");
        require(!sender.voted, "You already voted, cannot delegate");
        require(msg.sender != _to, "You cannot delegate to yourself");
        while(voters[_to].delegate != address(0)){
            _to = voters[_to].delegate;
            require(_to != msg.sender, "Found loop in delegation!");
        }

        Voter storage _delegate = voters[_to];
        require(delegate.weight > 0, "Delegate has no right to vote");
        sender.voted = true;
        sender.delegate = _to;
        if(!delegate.voted) {
            delegate.weight += sender.weight;
        } else {
            proposals[delegate.vote].voteCount += sender.weight;
        }

    }
    function vote(uint _activeProposalId, VotingOptions voteOption) external {
        Voter memory sender = voters[msg.sender];
        Proposal memory proposal = activeProposals[_activeProposalId];
        require(activeProposals[_activeProposalId].status == Status.Pending, "Proposal not Pending");
        require(block.timestamp < proposal.creationTime + votingDuration, "Voting Period is over");
        require(sender.weight >= 0,"You have no right to Vote!");
        require(!sender.voted, "Already Voted!");
        uint256 userWeight = weight(msg.sender);
        if (voteOption == VotingOptions.Yes) {
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
    function proposalResult(uint256 _proposalId) public view returns(Status status){
        Proposal memory proposal = proposals[_proposalId];
        //nedd to add if same votecount, what happens
        require(block.timestamp >= proposal.creationTime, "Voting still in progress");
        if (proposal.acceptedVotes > proposal.rejectedVotes) {
            proposal.status = status.Accepted;
        }else if (proposal.rejectedVotes > proposal.acceptedVotes) {
            proposal.status = status.Rejected;            
        } else {
            proposal.status = status.Indecisive;
        }   
        emit proposalResult(_proposalId, proposal.status);   
        return proposal.status;        
        }              
    function getUserProposals() external view returns(Proposal[] memory) {
        Proposal[] memory userProposals = new Proposal[](userProposalCount[msg.sender]);
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
