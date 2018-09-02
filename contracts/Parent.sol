pragma solidity ^0.4.23;

import "./lib/ECTools.sol";
import "./lib/token/HumanStandardToken.sol";
import "./lib/ownership/Ownable.sol";

/// @title Set-Plasma - A layer2 hub and spoke payment network based on State-channels and Plasma
/// @author Nathan Ginnever

contract Parent is Ownable {

    string public constant NAME = "Set-Plasma";
    string public constant VERSION = "0.0.1";

    uint256 public numChannels = 0;
    mapping(uint256 => bytes32) public plasmaChain;

    event DidLCOpen (
        bytes32 indexed channelId,
        address indexed partyA,
        address indexed partyI,
        uint256 balanceA,
        uint256 LCopenTimeout
    );

    event DidLCJoin (
        bytes32 indexed channelId,
        uint256 balanceI
    );

    event DidLCDeposit (
        bytes32 indexed channelId,
        address indexed recipient,
        uint256 deposit
    );

    event DidLCUpdateState (
        bytes32 indexed channelId, 
        uint256 sequence, 
        uint256 numOpenVc, 
        uint256 balanceA, 
        uint256 balanceI, 
        bytes32 vcRoot,
        uint256 updateLCtimeout
    );

    event DidLCClose (
        bytes32 indexed channelId,
        uint256 sequence,
        uint256 balanceA,
        uint256 balanceI
    );

    event DidVCInit (
        bytes32 indexed lcId, 
        bytes32 indexed vcId, 
        bytes proof, 
        uint256 sequence, 
        address partyA, 
        address partyB, 
        uint256 balanceA, 
        uint256 balanceB 
    );

    event DidVCSettle (
        bytes32 indexed lcId, 
        bytes32 indexed vcId,
        uint256 updateSeq, 
        uint256 updateBalA, 
        uint256 updateBalB,
        address challenger,
        uint256 updateVCtimeout
    );

    event DidVCClose(
        bytes32 indexed lcId, 
        bytes32 indexed vcId, 
        uint256 balanceA, 
        uint256 balanceB
    );

    struct Channel {
        address[2] partyAddresses; // 0: partyA 1: partyI
        uint256[4] ethBalances; // 0: balanceA 1:balanceI 2:depositedA 3:depositedI
        uint256[4] erc20Balances; // 0: balanceA 1:balanceI 2:depositedA 3:depositedI
        uint256 initialDeposit; // represents either ether or erc20
        uint256 sequence;
        uint256 confirmTime;
        bytes32 VCrootHash;
        uint256 LCopenTimeout;
        uint256 updateLCtimeout; // when update LC times out
        bool isOpen; // true when both parties have joined
        bool isUpdateLCSettling;
        uint256 numOpenVC;
        HumanStandardToken token;
    }

    // virtual-channel state
    struct VirtualChannel {
        bool isClose;
        bool isInSettlementState;
        uint256 sequence;
        address challenger; // Initiator of challenge
        uint256 updateVCtimeout; // when update VC times out
        // channel state
        address partyA; // VC participant A
        address partyB; // VC participant B
        address partyI; // LC hub
        uint256[2] ethBalances;
        uint256[2] erc20Balances;
        uint256 bond;
        HumanStandardToken token;
    }

    mapping(bytes32 => VirtualChannel) public virtualChannels;
    mapping(bytes32 => Channel) public Channels;

    function submitBlock(bytes32 _block) onlyOwner {
      
    }

    function createChannel(bytes32 _lcID, address _partyI, uint256 _confirmTime, address _token, uint256 _balance) public payable {
        require(Channels[_lcID].partyAddresses[0] == address(0), "Channel has already been created.");
        require(_partyI != 0x0, "No partyI address provided to LC creation");
        // Set initial ledger channel state
        // Alice must execute this and we assume the initial state 
        // to be signed from this requirement
        // Alternative is to check a sig as in joinChannel
        Channels[_lcID].partyAddresses[0] = msg.sender;
        Channels[_lcID].partyAddresses[1] = _partyI;

        if(_token == address(0x0)) {
            require(msg.value == _balance, "state balance does not match sent value");
            Channels[_lcID].ethBalances[0] = msg.value;
        } else {
            Channels[_lcID].token = HumanStandardToken(_token);
            require(Channels[_lcID].token.transferFrom(msg.sender, this, _balance),"CreateChannel: token transfer failure");
            Channels[_lcID].erc20Balances[0] = _balance;
        }

        Channels[_lcID].sequence = 0;
        Channels[_lcID].confirmTime = _confirmTime;
        // is close flag, lc state sequence, number open vc, vc root hash, partyA... 
        //Channels[_lcID].stateHash = keccak256(uint256(0), uint256(0), uint256(0), bytes32(0x0), bytes32(msg.sender), bytes32(_partyI), balanceA, balanceI);
        Channels[_lcID].LCopenTimeout = now + _confirmTime;
        Channels[_lcID].initialDeposit = _balance;

        emit DidLCOpen(_lcID, msg.sender, _partyI, msg.value, Channels[_lcID].LCopenTimeout);
    }

    function LCOpenTimeout(bytes32 _lcID) public {
        require(msg.sender == Channels[_lcID].partyAddresses[0] && Channels[_lcID].isOpen == false);
        require(now > Channels[_lcID].LCopenTimeout);

        if(Channels[_lcID].token == address(0x0)) {
            Channels[_lcID].partyAddresses[0].transfer(Channels[_lcID].ethBalances[0]);
            emit DidLCClose(_lcID, 0, Channels[_lcID].ethBalances[0], 0);
        } else {
            require(Channels[_lcID].token.transfer(Channels[_lcID].partyAddresses[0], Channels[_lcID].erc20Balances[0]),"CreateChannel: token transfer failure");
            emit DidLCClose(_lcID, 0, Channels[_lcID].erc20Balances[0], 0);
        }

        // only safe to delete since no action was taken on this channel
        delete Channels[_lcID];
    }

    function joinChannel(bytes32 _lcID, uint256 _balance) public payable {
        // require the channel is not open yet
        require(Channels[_lcID].isOpen == false);
        require(msg.sender == Channels[_lcID].partyAddresses[1]);

        if(Channels[_lcID].token == address(0x0)) {
            require(msg.value == _balance, "state balance does not match sent value");
            Channels[_lcID].ethBalances[1] = msg.value;
        } else {
            require(Channels[_lcID].token.transferFrom(msg.sender, this, _balance),"joinChannel: token transfer failure");
            Channels[_lcID].erc20Balances[0] = _balance;          
        }

        Channels[_lcID].initialDeposit+=_balance;
        // no longer allow joining functions to be called
        Channels[_lcID].isOpen = true;
        numChannels++;

        emit DidLCJoin(_lcID, msg.value);
    }


    // additive updates of monetary state
    function deposit(bytes32 _lcID, address recipient, uint256 _balance, bool isToken) public payable {
        require(Channels[_lcID].isOpen == true, "Tried adding funds to a closed channel");
        require(recipient == Channels[_lcID].partyAddresses[0] || recipient == Channels[_lcID].partyAddresses[1]);

        //if(Channels[_lcID].token)

        if (Channels[_lcID].partyAddresses[0] == recipient) {
            if(isToken) {
                require(Channels[_lcID].token.transferFrom(msg.sender, this, _balance),"deposit: token transfer failure");
                Channels[_lcID].erc20Balances[2] += _balance;
            } else {
                require(msg.value == _balance, "state balance does not match sent value");
                Channels[_lcID].ethBalances[2] += msg.value;
            }
        }

        if (Channels[_lcID].partyAddresses[1] == recipient) {
            if(isToken) {
                require(Channels[_lcID].token.transferFrom(msg.sender, this, _balance),"deposit: token transfer failure");
                Channels[_lcID].erc20Balances[3] += _balance;
            } else {
                require(msg.value == _balance, "state balance does not match sent value");
                Channels[_lcID].ethBalances[3] += msg.value; 
            }
        }
        
        emit DidLCDeposit(_lcID, recipient, msg.value);
    }

    // TODO: Check there are no open virtual channels, the client should have cought this before signing a close LC state update
    function consensusCloseChannel(
        bytes32 _lcID, 
        uint256 _sequence, 
        uint256[4] _balances, // 0: ethBalanceA 1:ethBalanceI 2:tokenBalanceA 3:tokenBalanceI
        string _sigA, 
        string _sigI
    ) 
        public 
    {
        // assume num open vc is 0 and root hash is 0x0
        //require(Channels[_lcID].sequence < _sequence);
        require(Channels[_lcID].isOpen == true);
        uint256 totalEthDeposit = Channels[_lcID].ethBalances[2] + Channels[_lcID].ethBalances[3];
        uint256 totalTokenDeposit = Channels[_lcID].erc20Balances[2] + Channels[_lcID].erc20Balances[3];
        uint256 totalDeposit = Channels[_lcID].initialDeposit + totalEthDeposit + totalTokenDeposit;
        require(totalDeposit == _balances[0] + _balances[1] + _balances[2] + _balances[3]);

        bytes32 _state = keccak256(
            abi.encodePacked(
                true,
                _sequence,
                uint256(0),
                bytes32(0x0),
                Channels[_lcID].partyAddresses[0], 
                Channels[_lcID].partyAddresses[1], 
                _balances[0], 
                _balances[1],
                _balances[2],
                _balances[3]
            )
        );

        require(Channels[_lcID].partyAddresses[0] == ECTools.recoverSigner(_state, _sigA));
        require(Channels[_lcID].partyAddresses[1] == ECTools.recoverSigner(_state, _sigI));

        Channels[_lcID].isOpen = false;

        if(_balances[0] != 0 || _balances[1] != 0) {
            Channels[_lcID].partyAddresses[0].transfer(_balances[0]);
            Channels[_lcID].partyAddresses[1].transfer(_balances[1]);
        }

        if(_balances[2] != 0 || _balances[3] != 0) {
            require(Channels[_lcID].token.transfer(Channels[_lcID].partyAddresses[0], _balances[2]),"happyCloseChannel: token transfer failure");
            require(Channels[_lcID].token.transfer(Channels[_lcID].partyAddresses[1], _balances[3]),"happyCloseChannel: token transfer failure");          
        }

        numChannels--;

        emit DidLCClose(_lcID, _sequence, _balances[0], _balances[1]);
    }

    // Byzantine functions

    function updateLCstate(
        bytes32 _lcID, 
        uint256[6] updateParams, // [sequence, numOpenVc, ethbalanceA, ethbalanceI, tokenbalanceA, tokenbalanceI]
        bytes32 _VCroot, 
        string _sigA, 
        string _sigI
    ) 
        public 
    {
        require(Channels[_lcID].isOpen);
        require(Channels[_lcID].sequence < updateParams[0]); // do same as vc sequence check
        require(Channels[_lcID].ethBalances[0] + Channels[_lcID].ethBalances[1] >= updateParams[2] + updateParams[3]);
        require(Channels[_lcID].erc20Balances[0] + Channels[_lcID].erc20Balances[1] >= updateParams[4] + updateParams[5]);

        if(Channels[_lcID].isUpdateLCSettling == true) { 
          require(Channels[_lcID].updateLCtimeout > now);
        }
      
        bytes32 _state = keccak256(
            abi.encodePacked(
                false, 
                updateParams[0], 
                updateParams[1], 
                _VCroot, 
                Channels[_lcID].partyAddresses[0], 
                Channels[_lcID].partyAddresses[1], 
                updateParams[2], 
                updateParams[3],
                updateParams[4], 
                updateParams[5]
            )
        );

        require(Channels[_lcID].partyAddresses[0] == ECTools.recoverSigner(_state, _sigA));
        require(Channels[_lcID].partyAddresses[1] == ECTools.recoverSigner(_state, _sigI));

        // update LC state
        Channels[_lcID].sequence = updateParams[0];
        Channels[_lcID].numOpenVC = updateParams[1];
        Channels[_lcID].ethBalances[0] = updateParams[2];
        Channels[_lcID].ethBalances[1] = updateParams[3];
        Channels[_lcID].erc20Balances[0] = updateParams[4];
        Channels[_lcID].erc20Balances[1] = updateParams[5];
        Channels[_lcID].VCrootHash = _VCroot;
        Channels[_lcID].isUpdateLCSettling = true;
        Channels[_lcID].updateLCtimeout = now + Channels[_lcID].confirmTime;

        // make settlement flag

        emit DidLCUpdateState (
            _lcID, 
            updateParams[0], 
            updateParams[1], 
            updateParams[2], 
            updateParams[3], 
            _VCroot,
            Channels[_lcID].updateLCtimeout
        );
    }

    // supply initial state of VC to "prime" the force push game  
    function initVCstate(
        bytes32 _lcID, 
        bytes32 _vcID, 
        bytes _proof, 
        address _partyA, 
        address _partyB, 
        uint256 _bond,
        uint256[4] _balances, // 0: ethBalanceA 1:ethBalanceI 2:tokenBalanceA 3:tokenBalanceI
        string sigA
    ) 
        public 
    {
        require(Channels[_lcID].isOpen, "LC is closed.");
        // sub-channel must be open
        require(!virtualChannels[_vcID].isClose, "VC is closed.");
        // Check time has passed on updateLCtimeout and has not passed the time to store a vc state
        require(Channels[_lcID].updateLCtimeout < now, "LC timeout over.");
        // prevent rentry of initializing vc state
        require(virtualChannels[_vcID].updateVCtimeout == 0);
        // partyB is now Ingrid
        bytes32 _initState = keccak256(
            abi.encodePacked(_vcID, uint256(0), _partyA, _partyB, _bond, _balances[0], _balances[1], _balances[2], _balances[3])
        );

        // Make sure Alice has signed initial vc state (A/B in oldState)
        require(_partyA == ECTools.recoverSigner(_initState, sigA));

        // Check the oldState is in the root hash
        require(_isContained(_initState, _proof, Channels[_lcID].VCrootHash) == true);

        virtualChannels[_vcID].partyA = _partyA; // VC participant A
        virtualChannels[_vcID].partyB = _partyB; // VC participant B
        virtualChannels[_vcID].sequence = uint256(0);
        virtualChannels[_vcID].ethBalances[0] = _balances[0];
        virtualChannels[_vcID].ethBalances[1] = _balances[1];
        virtualChannels[_vcID].erc20Balances[0] = _balances[2];
        virtualChannels[_vcID].erc20Balances[1] = _balances[3];
        virtualChannels[_vcID].bond = _bond;
        virtualChannels[_vcID].updateVCtimeout = now + Channels[_lcID].confirmTime;

        emit DidVCInit(_lcID, _vcID, _proof, uint256(0), _partyA, _partyB, _balances[0], _balances[1]);
    }

    //TODO: verify state transition since the hub did not agree to this state
    // make sure the A/B balances are not beyond ingrids bonds  
    // Params: vc init state, vc final balance, vcID
    function settleVC(
        bytes32 _lcID, 
        bytes32 _vcID, 
        uint256 updateSeq, 
        address _partyA, 
        address _partyB,
        uint256[4] updateBal, // [ethupdateBalA, ethupdateBalB, tokenupdateBalA, tokenupdateBalB]
        string sigA
    ) 
        public 
    {
        require(Channels[_lcID].isOpen, "LC is closed.");
        // sub-channel must be open
        require(!virtualChannels[_vcID].isClose, "VC is closed.");
        require(virtualChannels[_vcID].sequence < updateSeq, "VC sequence is higher than update sequence.");
        require(virtualChannels[_vcID].ethBalances[1] < updateBal[1] || 
                virtualChannels[_vcID].erc20Balances[1] < updateBal[3], "State updates may only increase recipient balance.");
        require(virtualChannels[_vcID].bond == updateBal[0] + updateBal[1] + updateBal[2] + updateBal[3], "Incorrect balances for bonded amount");
        // Check time has passed on updateLCtimeout and has not passed the time to store a vc state
        // virtualChannels[_vcID].updateVCtimeout should be 0 on uninitialized vc state, and this should
        // fail if initVC() isn't called first
        //require(Channels[_lcID].updateLCtimeout < now && now < virtualChannels[_vcID].updateVCtimeout);
        require(Channels[_lcID].updateLCtimeout < now); // for testing!

        bytes32 _updateState = keccak256(
            abi.encodePacked(_vcID, updateSeq, _partyA, _partyB, virtualChannels[_vcID].bond, updateBal[0], updateBal[1], updateBal[2], updateBal[3])
        );

        // Make sure Alice has signed a higher sequence new state
        require(virtualChannels[_vcID].partyA == ECTools.recoverSigner(_updateState, sigA));

        // store VC data
        // we may want to record who is initiating on-chain settles
        virtualChannels[_vcID].challenger = msg.sender;
        virtualChannels[_vcID].sequence = updateSeq;

        // channel state
        virtualChannels[_vcID].ethBalances[0] = updateBal[0];
        virtualChannels[_vcID].ethBalances[1] = updateBal[1];
        virtualChannels[_vcID].erc20Balances[0] = updateBal[2];
        virtualChannels[_vcID].erc20Balances[1] = updateBal[3];

        virtualChannels[_vcID].updateVCtimeout = now + Channels[_lcID].confirmTime;
        virtualChannels[_vcID].isInSettlementState = true;

        emit DidVCSettle(_lcID, _vcID, updateSeq, updateBal[0], updateBal[1], msg.sender, virtualChannels[_vcID].updateVCtimeout);
    }

    function closeVirtualChannel(bytes32 _lcID, bytes32 _vcID) public {
        // require(updateLCtimeout > now)
        require(Channels[_lcID].isOpen, "LC is closed.");
        require(virtualChannels[_vcID].isInSettlementState, "VC is not in settlement state.");
        require(virtualChannels[_vcID].updateVCtimeout < now, "Update vc timeout has not elapsed.");
        // reduce the number of open virtual channels stored on LC
        Channels[_lcID].numOpenVC--;
        // close vc flags
        virtualChannels[_vcID].isClose = true;
        // re-introduce the balances back into the LC state from the settled VC
        // decide if this lc is alice or bob in the vc
        if(virtualChannels[_vcID].partyA == Channels[_lcID].partyAddresses[0]) {
            Channels[_lcID].ethBalances[0] += virtualChannels[_vcID].ethBalances[0];
            Channels[_lcID].ethBalances[1] += virtualChannels[_vcID].ethBalances[1];

            Channels[_lcID].erc20Balances[0] += virtualChannels[_vcID].erc20Balances[0];
            Channels[_lcID].erc20Balances[1] += virtualChannels[_vcID].erc20Balances[1];
        } else if (virtualChannels[_vcID].partyB == Channels[_lcID].partyAddresses[0]) {
            Channels[_lcID].ethBalances[0] += virtualChannels[_vcID].ethBalances[1];
            Channels[_lcID].ethBalances[1] += virtualChannels[_vcID].ethBalances[0];

            Channels[_lcID].erc20Balances[0] += virtualChannels[_vcID].erc20Balances[1];
            Channels[_lcID].erc20Balances[1] += virtualChannels[_vcID].erc20Balances[0];
        }

        emit DidVCClose(_lcID, _vcID, virtualChannels[_vcID].erc20Balances[0], virtualChannels[_vcID].erc20Balances[1]);
    }


    // todo: allow ethier lc.end-user to nullify the settled LC state and return to off-chain
    function byzantineCloseChannel(bytes32 _lcID) public{
        // check settlement flag
        require(Channels[_lcID].isUpdateLCSettling == true);
        require(Channels[_lcID].numOpenVC == 0);
        require(Channels[_lcID].updateLCtimeout < now, "LC timeout over.");

        // if off chain state update didnt reblance deposits, just return to deposit owner
        uint256 totalEthDeposit = Channels[_lcID].ethBalances[2] + Channels[_lcID].ethBalances[3];
        uint256 totalTokenDeposit = Channels[_lcID].erc20Balances[2] + Channels[_lcID].erc20Balances[3];
        uint256 totalDeposit = Channels[_lcID].initialDeposit + totalEthDeposit + totalTokenDeposit;

        uint256 possibleTotalBeforeDeposit = Channels[_lcID].ethBalances[0] + Channels[_lcID].ethBalances[1] + Channels[_lcID].erc20Balances[0] + Channels[_lcID].erc20Balances[1];

        if(possibleTotalBeforeDeposit < totalDeposit) {
            Channels[_lcID].ethBalances[0]+=Channels[_lcID].ethBalances[2];
            Channels[_lcID].ethBalances[1]+=Channels[_lcID].ethBalances[3];

            Channels[_lcID].erc20Balances[0]+=Channels[_lcID].erc20Balances[2];
            Channels[_lcID].erc20Balances[1]+=Channels[_lcID].erc20Balances[3];
        } else {
            require(possibleTotalBeforeDeposit == totalDeposit);
        }

        // reentrancy
        uint256 ethbalanceA = Channels[_lcID].ethBalances[0];
        uint256 ethbalanceI = Channels[_lcID].ethBalances[1];
        uint256 tokenbalanceA = Channels[_lcID].erc20Balances[0];
        uint256 tokenbalanceI = Channels[_lcID].erc20Balances[1];

        Channels[_lcID].ethBalances[0] = 0;
        Channels[_lcID].ethBalances[1] = 0;
        Channels[_lcID].erc20Balances[0] = 0;
        Channels[_lcID].erc20Balances[1] = 0;

        if(ethbalanceA != 0 || ethbalanceI != 0) {
            Channels[_lcID].partyAddresses[0].transfer(ethbalanceA);
            Channels[_lcID].partyAddresses[1].transfer(ethbalanceI);
        }

        if(tokenbalanceA != 0 || tokenbalanceI != 0) {
            require(Channels[_lcID].token.transfer(Channels[_lcID].partyAddresses[0], tokenbalanceA),"happyCloseChannel: token transfer failure");
            require(Channels[_lcID].token.transfer(Channels[_lcID].partyAddresses[1], tokenbalanceI),"happyCloseChannel: token transfer failure");          
        }

        Channels[_lcID].isOpen = false;
        numChannels--;

        emit DidLCClose(_lcID, Channels[_lcID].sequence, ethbalanceA, ethbalanceI);
    }

    function _isContained(bytes32 _hash, bytes _proof, bytes32 _root) internal pure returns (bool) {
        bytes32 cursor = _hash;
        bytes32 proofElem;

        for (uint256 i = 64; i <= _proof.length; i += 32) {
            assembly { proofElem := mload(add(_proof, i)) }

            if (cursor < proofElem) {
                cursor = keccak256(abi.encodePacked(cursor, proofElem));
            } else {
                cursor = keccak256(abi.encodePacked(proofElem, cursor));
            }
        }

        return cursor == _root;
    }

    function getChannel(bytes32 id) public view returns (
        address[2],
        uint256[4],
        uint256[4],
        uint256,
        uint256,
        uint256,
        bytes32,
        uint256,
        uint256,
        bool,
        bool,
        uint256
    ) {
        Channel memory channel = Channels[id];
        return (
            channel.partyAddresses,
            channel.ethBalances,
            channel.erc20Balances,
            channel.initialDeposit,
            channel.sequence,
            channel.confirmTime,
            channel.VCrootHash,
            channel.LCopenTimeout,
            channel.updateLCtimeout,
            channel.isOpen,
            channel.isUpdateLCSettling,
            channel.numOpenVC
        );
    }

    function getVirtualChannel(bytes32 id) public view returns(
        bool,
        bool,
        uint256,
        address,
        uint256,
        address,
        address,
        address,
        uint256[2],
        uint256[2],
        uint256
    ) {
        VirtualChannel memory virtualChannel = virtualChannels[id];
        return(
            virtualChannel.isClose,
            virtualChannel.isInSettlementState,
            virtualChannel.sequence,
            virtualChannel.challenger,
            virtualChannel.updateVCtimeout,
            virtualChannel.partyA,
            virtualChannel.partyB,
            virtualChannel.partyI,
            virtualChannel.ethBalances,
            virtualChannel.erc20Balances,
            virtualChannel.bond
        );
    }
}
