import "./Owned.sol";
import "./LowLevelStringManipulator.sol";
import "./MiniMeToken.sol";

pragma solidity ^0.4.13;

contract DelegativeDemocracy {
    function delegationOfAt(address _who, uint _block) constant returns(address);
    function influenceOfAt(address _who, MiniMeToken _token, uint _block) constant returns(uint256);
    function delegate(address _to);
}

contract IPollContract {
    function deltaVote(int _amount, bytes32 _ballot) returns (bool _succes);
    function pollType() constant returns (bytes32);
    function question() constant returns (string);
}

contract IPollFactory {
    function create(bytes _description) returns(address);
}

contract PollManager is LowLevelStringManipulator, Owned {

    struct VoteLog {
        bytes32 ballot;
        uint amount;
    }

    struct Poll {
        uint startBlock;
        uint endBlock;
        address token;
        address delegation;
        address pollContract;
        bool canceled;
        mapping(address => VoteLog) votes;
    }

    Poll[] _polls;

    MiniMeTokenFactory public tokenFactory;

    function PollManager(address _tokenFactory) {
        tokenFactory = MiniMeTokenFactory(_tokenFactory);
    }

    function addPoll(
        address _delegation,
        address _token,
        uint _startBlock,
        uint _endBlock,
        address _pollFactory,
        bytes _description) onlyOwner returns (uint _idPoll)
    {
        require (_endBlock > _startBlock);
        require (_endBlock > getBlockNumber());
        _idPoll = _polls.length;
        _polls.length ++;
        Poll storage p = _polls[ _idPoll ];
        p.startBlock = _startBlock;
        p.endBlock = _endBlock;
        p.delegation = _delegation;

        var (name,symbol) = getTokenNameSymbol(_token);
        string memory proposalName = strConcat(name , "_", uint2str(_idPoll));
        string memory proposalSymbol = strConcat(symbol, "_", uint2str(_idPoll));


        p.pollContract = IPollFactory(_pollFactory).create(_description);

        assert (p.pollContract != 0);
    }

    function cancelPoll(uint _idPoll) onlyOwner {
        require (_idPoll < _polls.length);
        Poll storage p = _polls[_idPoll];
        require (getBlockNumber() < p.endBlock);
        p.canceled = true;
        PollCanceled(_idPoll);
    }

    function vote(uint _idPoll, bytes32 _ballot) {
        require (_idPoll < _polls.length);
        Poll storage p = _polls[_idPoll];
        require (getBlockNumber() >= p.startBlock);
        require (getBlockNumber() < p.endBlock);
        require (!p.canceled);

        unvote(_idPoll);
        
        uint amount;
        if (p.delegation != 0x0){
            amount = DelegativeDemocracy(p.delegation).influenceOfAt(msg.sender, MiniMeToken(p.token), p.startBlock);
        } else {
            amount = MiniMeToken(p.token).balanceOfAt(msg.sender, p.startBlock);
        }

        require (amount > 0);

        p.votes[msg.sender].ballot = _ballot;
        p.votes[msg.sender].amount = amount;

        assert (IPollContract(p.pollContract).deltaVote(int(amount), _ballot));

        Vote(_idPoll, msg.sender, _ballot, amount);
    }

    function unvote(uint _idPoll) {
        require (_idPoll < _polls.length);
        Poll storage p = _polls[_idPoll];
        require (getBlockNumber() >= p.startBlock);
        require (getBlockNumber() < p.endBlock);
        require (!p.canceled);

        uint amount = p.votes[msg.sender].amount;
        bytes32 ballot = p.votes[msg.sender].ballot;
        require (amount > 0);

        assert (IPollContract(p.pollContract).deltaVote(-int(amount), ballot));


        p.votes[msg.sender].ballot = 0x0;
        p.votes[msg.sender].amount = 0;

        Unvote(_idPoll, msg.sender, ballot, amount);
    }

// Constant Helper Function

    function nPolls() constant returns(uint) {
        return _polls.length;
    }

    function poll(uint _idPoll) constant returns(
        uint _startBlock,
        uint _endBlock,
        address _token,
        address _delegation,
        address _pollContract,
        bool _canceled,
        bytes32 _pollType,
        string _question,
        bool _finalized,
        uint _totalCensus
    ) {
        require (_idPoll < _polls.length);
        Poll storage p = _polls[_idPoll];
        _startBlock = p.startBlock;
        _endBlock = p.endBlock;
        _token = p.token;
        _delegation = p.delegation;
        _pollContract = p.pollContract;
        _canceled = p.canceled;
        _pollType = IPollContract(p.pollContract).pollType();
        _question = getString(p.pollContract, bytes4(sha3("question()")));
        _finalized = (!p.canceled) && (getBlockNumber() >= _endBlock);
        _totalCensus = MiniMeToken(p.token).totalSupplyAt(p.startBlock);
    }

    function getVote(uint _idPoll, address _voter) constant returns (bytes32 _ballot, uint _amount) {
        require (_idPoll < _polls.length);
        Poll storage p = _polls[_idPoll];

        _ballot = p.votes[_voter].ballot;
        _amount = p.votes[_voter].amount;
    }

    function proxyPayment(address ) payable returns(bool) {
        return false;
    }


    function onTransfer(address , address , uint ) returns(bool) {
        return true;
    }

    function onApprove(address , address , uint ) returns(bool) {
        return true;
    }


    function getBlockNumber() internal constant returns (uint) {
        return block.number;
    }

    event Vote(uint indexed idPoll, address indexed _voter, bytes32 ballot, uint amount);
    event Unvote(uint indexed idPoll, address indexed _voter, bytes32 ballot, uint amount);
    event PollCanceled(uint indexed idPoll);



}
