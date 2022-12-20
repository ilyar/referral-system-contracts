pragma ton-solidity >= 0.39.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensBurnCallback.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/ITokenWallet.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IVersioned.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/SID.sol";


import '@broxus/contracts/contracts/access/InternalOwner.sol';
import '@broxus/contracts/contracts/utils/CheckPubKey.sol';
import '@broxus/contracts/contracts/utils/RandomNonce.sol';
import "@broxus/contracts/contracts/libraries/MsgFlag.sol";

import "../RefLast.sol";
import "../RefLastPlatform.sol";
import "../RefAccountPlatform.sol";
import "../ProjectPlatform.sol";

import "../interfaces/IRefSystem.sol";
import "../interfaces/IUpgradeable.sol";
import "../interfaces/IRefProject.sol";

abstract contract RefSystemBase is
    IRefSystem,
    IVersioned,
    InternalOwner,
    SID
{   
    uint32 version_;
    TvmCell public _platformCode;
    
    uint128 constant BPS = 1_000_000;
    uint256 public _projectCounter;

    address public _refFactory;
    TvmCell public _refLastCode;
    TvmCell public _refLastPlatformCode;
    TvmCell public _accountCode;
    TvmCell public _accountPlatformCode;
    TvmCell public _projectCode;
    TvmCell public _projectPlatformCode;

    uint128 public _deployAccountValue;
    uint128 public _deployRefLastValue;
    uint128 public _systemFee;
    
    function _reserve() virtual internal returns (uint128) {
        return 0.2 ton;
    }

    function _nextProjectId() internal returns (uint256 id) {
        id = _projectCounter;
        _projectCounter += 1;
    }

    function setSystemFee(uint128 fee) override external onlyOwner {
        require(fee <= BPS, 500, "Invalid Param");
        _systemFee = fee;
    }

    function setDeployAccountValue(uint128 value) override external onlyOwner {
        _deployAccountValue = value;
    }

    function setDeployRefLastValue(uint128 value) override external onlyOwner {
        _deployRefLastValue = value;
    }

    function onAcceptTokensTransfer(
        address tokenRoot,
        uint128 amount,
        address sender,
        address senderWallet,
        address remainingGasTo,
        TvmCell payload
    ) override external {
        require(amount != 0, 401, "Invalid Amount");
        (uint256 projectId, address referred, address referrer) = abi.decode(payload, (uint256, address, address));
        address targetProject = _deriveProject(projectId);
        TvmCell acceptParams = abi.encode(msg.sender, tokenRoot, amount, sender, senderWallet, remainingGasTo, projectId, referred, referrer);
        
        IRefProject(targetProject).meta{
            callback: RefSystemBase.getProjectMeta,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(acceptParams);
    }

    function onAcceptTokensTransferPayloadEncoder(uint256 projectId, address referred, address referrer) override responsible external returns (TvmCell) {
        return abi.encode(projectId, referred, referrer);
    }

    function getProjectMeta(
        bool isApproved,
        address projectOwner,
        uint128 cashback,
        uint128 projectFee,
        TvmCell acceptParams
    ) external {
        (address tokenWallet,
        address tokenRoot,
        uint128 amount,
        address sender,
        address senderWallet,
        address remainingGasTo,
        uint256 projectId,
        address referred,
        address referrer) = abi.decode(acceptParams, (address, address, uint128, address, address, address, uint256, address, address));
        require(msg.sender == _deriveProject(projectId), 400, "Not a valid Project");
        require(amount != 0, 400, "Invalid Amount");
        
        // If Amount or Project Invalid, simply receive full reward
        if(!isApproved || (uint(BPS) < uint(_systemFee) + uint(projectFee) + uint(cashback))) {
            _deployRefAccount(owner, tokenWallet, amount, sender, remainingGasTo);
            return;
        }

        // Allocate to System Owner
        uint128 systemReward = uint128(math.muldiv(uint(amount),uint(_systemFee),uint(BPS)));
        if(systemReward != 0) { _deployRefAccount(owner, tokenWallet, systemReward, sender, remainingGasTo); }
        
        // Allocate to Project Owner
        uint128 projectReward = uint128(math.muldiv(uint(amount),uint(projectFee),uint(BPS)));
        if(projectReward != 0) { _deployRefAccount(projectOwner, tokenWallet, projectReward, sender, remainingGasTo); }
        
        // Allocate to Referred
        uint128 cashbackReward = uint128(math.muldiv(uint(amount),uint(cashback),uint(BPS)));
        if(cashbackReward != 0) { _deployRefAccount(referred, tokenWallet, (amount*cashback)/BPS, sender, remainingGasTo); }
        
        // Allocate to Referrer
        uint128 reward = amount - systemReward - projectReward - cashbackReward;
        if (reward != 0) { _deployRefAccount(referrer, tokenWallet, reward, sender, remainingGasTo); }
        
        // Update referrer
        _deployRefLast(referrer, tokenWallet, referred, referrer, amount, sender, remainingGasTo);
    }

    function requestTransfer(
        address recipient,
        address tokenWallet,
        uint128 balance,
        address remainingGasTo,
        bool notify,
        TvmCell payload
    ) override external {
        require(msg.sender == _deriveRefAccount(recipient), 400, "Invalid Account");
        ITokenWallet(tokenWallet).transfer{flag: MsgFlag.REMAINING_GAS, value: 0 }(balance, recipient, 0.5 ton, remainingGasTo, notify, payload);
    }

    function deriveProject(uint256 id) override external responsible returns (address) {
       return _deriveProject(id);
    }

    function deriveRefAccount(address owner) override external responsible returns (address) {
       return _deriveRefAccount(owner);
    }

    function deriveRefLast(address owner) override external responsible returns (address) {
        return _deriveRefLast(owner);
    }

    function deployProject(
        address refSystem,
        uint128 projectFee,
        uint128 cashbackFee,
        address sender,
        address remainingGasTo
    ) override external returns (address) {
        return new ProjectPlatform {
            stateInit: _buildProjectInitData(_nextProjectId()),
            value: 0,
            wid: address(this).wid,
            bounce: true,
            flag: MsgFlag.REMAINING_GAS
        }(
            _projectCode,
            version_,
            _refFactory,
            msg.sender,
            projectFee,
            cashbackFee,
            sender,
            remainingGasTo
        );
    }

    function deployRefAccount(
        address[] recipients,
        address tokenWallet,
        uint128[] rewards,
        address sender,
        address remainingGasTo
    ) external onlyOwner returns (address) {
        require(recipients.length == rewards.length, 405, "Invalid Params");
        for (uint256 i = 0; i < recipients.length; i++) {
            _deployRefAccount(recipients[i], tokenWallet, rewards[i], sender, remainingGasTo);
        }
    }

    function deployRefLast(
        address owner,
        address lastRefWallet,
        address lastReferred,
        address lastReferrer,
        uint128 lastRefReward,
        address sender,
        address remainingGasTo
    ) external onlyOwner returns (address) {
        return _deployRefLast(owner, lastRefWallet,lastReferred,lastReferrer,lastRefReward,sender,remainingGasTo);
    }

    function setProjectApproval(uint256 projectId, bool value) override external onlyOwner  {
        IRefProject(_deriveProject(projectId)).setApproval(value);
    }

    

    function _deriveProject(uint256 id) internal returns (address) {
        return address(tvm.hash(_buildProjectInitData(id)));
    }

    function _deriveRefAccount(address owner) internal returns (address) {
        return address(tvm.hash(_buildRefAccountInitData(owner)));
    }

    function _deriveRefLast(address owner) internal returns (address) {
        return address(tvm.hash(_buildRefLastInitData(owner)));
    }

    function _deployRefAccount(
        address recipient,
        address tokenWallet,
        uint128 reward,
        address sender,
        address remainingGasTo
    ) internal returns (address) {
        return new RefAccountPlatform {
            stateInit: _buildRefAccountInitData(recipient),
            value: _deployAccountValue,
            wid: address(this).wid,
            flag: 0,
            bounce: true
        }(_accountCode, version_, _refFactory, tokenWallet, reward, sender, remainingGasTo);
    }
    
    function _deployRefLast(
        address owner,
        address lastRefWallet,
        address lastReferred,
        address lastReferrer,
        uint128 lastRefReward,
        address sender,
        address remainingGasTo
    ) internal returns (address) {
        return new RefLastPlatform {
            stateInit: _buildRefLastInitData(owner),
            value: _deployRefLastValue,
            wid: address(this).wid,
            flag: 0,
            bounce: true
        }(_refLastCode, version_, _refFactory, lastRefWallet, lastReferred, lastReferrer, lastRefReward, sender, remainingGasTo);
    }

    function _buildProjectInitData(uint256 id) internal returns (TvmCell) {
        return tvm.buildStateInit({
            contr: ProjectPlatform,
            varInit: {
                root: address(this),
                id: id
            },
            pubkey: 0,
            code: _projectPlatformCode
        });
    }
    function _buildRefLastInitData(address owner) internal returns (TvmCell) {
        return tvm.buildStateInit({
            contr: RefLastPlatform,
            varInit: {
                root: address(this),
                owner: owner
            },
            pubkey: 0,
            code: _refLastPlatformCode
        });
    }

    function _buildRefAccountInitData(address target) internal returns (TvmCell) {
        return tvm.buildStateInit({
            contr: RefAccountPlatform,
            varInit: {
                root: address(this),
                owner: target
            },
            pubkey: 0,
            code: _accountPlatformCode
        });
    }

}