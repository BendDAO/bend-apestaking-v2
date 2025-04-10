//SPDX-License-Identifier: MIT

/*
ApeStake Smart Contract Disclaimer

The ApeStake smart contract (the “Smart Contract”) was developed at the direction of the ApeCoin DAO community pursuant
to a grant by the Ape Foundation.  The grant instructs the development of the Smart Contract and the developer’s user
interface to enable a non-exclusive, user friendly means of access to the rewards program offered to the APE community
by the Ape Foundation pursuant to the specifications set forth in AIPs 21/22. The Smart Contract is made up of free,
public, open-source or source-available software deployed on the Ethereum Blockchain.

Use Disclaimer.
Your use of the Smart Contract involves various risks, including, but not limited to, losses while digital
assets are being supplied and/or removed from the Smart Contract, losses due to the volatility of token price,
risks in connection with your personal wallet access, system failures, opportunity loss while participating in the
Smart Contract, loss of tokens in connection with non-fungible token transfers, risk of cyber attack and/or security
breach, risk of legal uncertainty and/or changes in legal environment, and additional risks which may be based upon
utilization of any third party other than the Smart Contract developer who provides you with access to the Smart
Contract. Before using the Smart Contract, you should review the relevant documentation to make sure you understand
how the Smart Contract works. Additionally, because you may be able to access the Smart Contract through other web or
mobile interfaces than the Smart Contract developer’s user interface provided pursuant to the Ape Foundation grant,
you are responsible for doing your own diligence on those interfaces to understand the fees and risks they present.

THE SMART CONTRACT IS PROVIDED "AS IS", AT YOUR OWN RISK, AND WITHOUT WARRANTIES OF ANY KIND.
The developer was contracted by APE Foundation to develop the initial code to implement AIP 21/22.
The developer does not own or control the staking rewards program, which is run on the Smart Contracts deployed on
the Ethereum blockchain.  Upgrades and modifications will be managed in a community-driven way by holders of the APE
governance token and may be undertaken and/or implemented with no involvement of the developer.

No liability.
No developer or entity involved in creating the Smart Contract or “platform as a service” will be liable for any
claims or damages whatsoever associated with your use, inability to use, or your interaction with the Smart Contract
or the developer’s user interface provided pursuant to the Ape Foundation grant, including any direct, indirect,
incidental, special, exemplary, punitive or consequential damages, or loss of profits, cryptocurrencies, tokens,
or anything else of value.

Access to Third Parties.
Any party who uses or provides access to the Smart Contract to third parties must (a) not provide such access in
violation of any applicable law or regulation, (b) inform such third parties of any and all risks, and (c) is solely
responsible to such third parties for any and all liability, claims or damages relating to such party’s provision of
access to the Smart Contract.
*/
pragma solidity 0.8.18;

import {SafeCastLib} from "./ApeCoinStaking/SafeCastLib.sol";
import {LibMap} from "./ApeCoinStaking/LibMap.sol";
import {Ownable} from "./ApeCoinStaking/Ownable.sol";
import {IShadowCallbackReceiver} from "./ApeCoinStaking/IShadowCallbackReceiver.sol";

interface INFTShadow {
    function ownerOf(uint256 tokenId) external view returns (address);

    function readWithCallback(
        uint256[] calldata tokenIds,
        uint32[] calldata eids,
        uint128 callbackGasLimit
    ) external payable returns (bytes32);

    function locked(uint256 tokenId) external view returns (bool);
}

interface IBeacon {
    function quoteRead(
        address baseCollectionAddress,
        uint256[] calldata tokenIds,
        uint32[] calldata dstEids,
        uint128 supplementalGasLimit
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);
}

/**
 * @title ApeCoin Staking Contract
 * @notice Stake ApeCoin across four different pools that release hourly rewards
 * @author HorizenLabs
 */
contract ApeCoinStaking is IShadowCallbackReceiver, Ownable {
    using SafeCastLib for uint256;
    using SafeCastLib for int256;

    using LibMap for LibMap.Uint16Map;
    using LibMap for LibMap.Uint128Map;

    struct PendingClaim {
        uint8 poolId;
        uint8 requestType;
        address caller;
        address recipient;
        uint96 numNfts;
        LibMap.Uint16Map tokenIds;
        LibMap.Uint128Map amounts;
    }

    /// @notice State for BAYC, MAYC, and BAKC Pools
    struct Pool {
        uint48 lastRewardedTimestampHour;
        uint16 lastRewardsRangeIndex;
        uint96 stakedAmount;
        uint96 accumulatedRewardsPerShare;
        TimeRange[] timeRanges;
    }

    /// @notice Pool rules valid for a given duration of time.
    /// @dev All TimeRange timestamp values must represent whole hours
    struct TimeRange {
        uint48 startTimestampHour;
        uint48 endTimestampHour;
        uint96 rewardsPerHour;
        uint96 capPerPosition;
    }

    /// @dev Convenience struct for front-end applications
    struct PoolUI {
        uint256 poolId;
        uint256 stakedAmount;
        TimeRange currentTimeRange;
    }

    /// @dev Per address amount and reward tracking
    struct Position {
        uint256 stakedAmount;
        int256 rewardsDebt;
    }

    mapping(bytes32 guid => PendingClaim claim) internal _pendingClaims;

    // @dev UI focused payload
    struct DashboardStake {
        uint256 poolId;
        uint256 tokenId;
        uint256 deposited;
        uint256 unclaimed;
        uint256 rewards24hr;
    }

    uint256 private constant _APE_COIN_PRECISION = 1e18;
    uint256 private constant _MIN_DEPOSIT = 1 * _APE_COIN_PRECISION;
    uint256 private constant _SECONDS_PER_HOUR = 3600;
    uint256 private constant _SECONDS_PER_MINUTE = 60;
    uint128 private constant _BASE_CALLBACK_GAS_LIMIT = 60_000;
    uint128 private constant _INCREMENTAL_CALLBACK_GAS_LIMIT = 15_000;

    uint256 private constant _BAYC_POOL_ID = 1;
    uint256 private constant _MAYC_POOL_ID = 2;
    uint256 private constant _BAKC_POOL_ID = 3;

    uint8 private constant _CLAIM_TYPE = 0;
    uint8 private constant _WITHDRAW_TYPE = 1;

    // leave pools[0] null and revert if trying to access it
    Pool[4] public pools;

    IBeacon private _beacon;

    uint32[] private _eids;

    /// @dev NFT contract mapping per pool
    mapping(uint256 => INFTShadow) public nftContracts;
    /// @dev poolId => tokenId => nft position
    mapping(uint256 => mapping(uint256 => Position)) public nftPosition;

    /**
     * Custom Events
     */
    event TimeRangeAdded(
        uint256 indexed poolId,
        uint256 index,
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 rewardsPerHour,
        uint256 capPerPosition
    );
    event UpdatePool(
        uint256 indexed poolId,
        uint256 lastRewardedBlock,
        uint256 stakedAmount,
        uint256 accumulatedRewardsPerShare
    );
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount, uint256 tokenId);
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, address recipient, uint256 tokenId);
    event Claim(address indexed user, uint256 indexed poolId, uint256 amount, uint256 tokenId);
    event RequestSubmitted(
        bytes32 indexed guid,
        address indexed caller,
        uint8 indexed poolId,
        uint8 requestType,
        uint256[] nfts,
        address recipient
    );
    event CallbackExecuted(bytes32 indexed guid);

    error RefundFailed();
    error InvalidAmount();
    error InvalidPoolId();
    error WithdrawFailed();
    error CallerNotOwner();
    error TransferFailed();
    error ZeroArrayLength();
    error EndNotWholeHour();
    error InsufficientFee();
    error InvalidRecipient();
    error DistributionEnded();
    error StartNotWholeHour();
    error ExceededCapAmount();
    error MismatchArrayLength();
    error ExceededStakedAmount();
    error DepositMoreThanOneAPE();
    error StartMustEqualLastEnd();
    error StartGreaterThanEnd();

    /**
     * @notice Construct a new ApeCoinStaking instance
     * @param _baycContractAddress The BAYC NFT contract address
     * @param _maycContractAddress The MAYC NFT contract address
     * @param _bakcContractAddress The BAKC NFT contract address
     */
    constructor(
        address beacon,
        address _baycContractAddress,
        address _maycContractAddress,
        address _bakcContractAddress
    ) {
        nftContracts[_BAYC_POOL_ID] = INFTShadow(_baycContractAddress);
        nftContracts[_MAYC_POOL_ID] = INFTShadow(_maycContractAddress);
        nftContracts[_BAKC_POOL_ID] = INFTShadow(_bakcContractAddress);
        _beacon = IBeacon(beacon);

        _initializeOwner(msg.sender);
    }

    modifier validPool(uint256 poolId) {
        if (poolId > _BAKC_POOL_ID || poolId < _BAYC_POOL_ID) {
            revert InvalidPoolId();
        }
        _;
    }

    // Refunds from LZ or other native currency transactions are forwarded to the owner
    receive() external payable {
        (bool success, ) = owner().call{value: msg.value}("");
        if (!success) revert RefundFailed();
    }

    // Deposit/Commit Methods
    /**
     * @notice Deposit ApeCoin to an NFT pool
     * @param poolId The pool ID
     * @param tokenIds Array of tokenIds
     * @param amounts Array of amounts
     * @dev Commits 1 or more NFTs, each with an ApeCoin amount to the NFT pool.\
     * Each NFT committed must attach an ApeCoin amount >= 1 ApeCoin and <= the NFT pool cap amount.
     */
    function deposit(
        uint256 poolId,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external payable validPool(poolId) {
        if (tokenIds.length == 0) revert ZeroArrayLength();
        if (tokenIds.length != amounts.length) revert MismatchArrayLength();

        uint256 totalDeposit = 0;
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            totalDeposit += amounts[i];
        }
        if (msg.value != totalDeposit) revert InvalidAmount();

        _depositNft(poolId, tokenIds, amounts);
    }

    // Claim Rewards Methods
    /**
     * @notice Claim rewards for an NFT pool and send to recipient
     * @param poolId The pool ID
     * @param tokenIds Array of tokenIds
     * @param recipient Address to send claim reward to
     */
    function claim(uint256 poolId, uint256[] calldata tokenIds, address recipient) external payable validPool(poolId) {
        if (tokenIds.length == 0) revert ZeroArrayLength();
        if (recipient == address(0)) revert InvalidRecipient();

        uint256 valueForFees = msg.value;
        valueForFees -= _requestClaim(poolId, tokenIds, recipient, valueForFees);

        _refundIfOver(valueForFees);
    }

    function claimSelf(uint256 poolId, uint256[] calldata tokenIds) external payable validPool(poolId) {
        if (tokenIds.length == 0) revert ZeroArrayLength();

        uint256 valueForFees = msg.value;
        valueForFees -= _requestClaim(poolId, tokenIds, msg.sender, valueForFees);

        _refundIfOver(valueForFees);
    }

    // Uncommit/Withdraw Methods
    /**
     * @notice Withdraw staked ApeCoin from the BAYC pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param tokenIds Array of tokenIds
     * @param amounts Array of amounts
     * @param recipient Address to send withdraw amount and claim to
     */
    function withdraw(
        uint256 poolId,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address recipient
    ) external payable validPool(poolId) {
        if (tokenIds.length == 0) revert ZeroArrayLength();
        if (tokenIds.length != amounts.length) revert MismatchArrayLength();
        if (recipient == address(0)) revert InvalidRecipient();

        uint256 valueForFees = msg.value;
        valueForFees -= _requestWithdraw(poolId, tokenIds, amounts, recipient, valueForFees);

        _refundIfOver(valueForFees);
    }

    /**
     * @notice Withdraw staked ApeCoin from the BAYC pool.  If withdraw is total staked amount, performs an automatic claim.
     * @param tokenIds Array of tokenIds
     * @param amounts Array of amounts
     */
    function withdrawSelf(
        uint256 poolId,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external payable validPool(poolId) {
        if (tokenIds.length == 0) revert ZeroArrayLength();
        if (tokenIds.length != amounts.length) revert MismatchArrayLength();

        uint256 valueForFees = msg.value;
        valueForFees -= _requestWithdraw(poolId, tokenIds, amounts, msg.sender, valueForFees);

        _refundIfOver(valueForFees);
    }

    /**
     * @notice Deposit ApeCoin to BAYC, MAYC, and BAKC pools
     * @param baycTokenIds Array of BAYC token IDs
     * @param maycTokenIds Array of MAYC token IDs
     * @param bakcTokenIds Array of BAKC token IDs
     * @param baycAmounts Array of BAYC staked amounts
     * @param maycAmounts Array of MAYC staked amounts
     * @param bakcAmounts Array of BAKC staked amounts
     */
    // function depositBatch(
    //     uint256[] calldata baycTokenIds,
    //     uint256[] calldata maycTokenIds,
    //     uint256[] calldata bakcTokenIds,
    //     uint256[] calldata baycAmounts,
    //     uint256[] calldata maycAmounts,
    //     uint256[] calldata bakcAmounts
    // ) external payable {
    //     if (baycTokenIds.length == 0 && maycTokenIds.length == 0 && bakcTokenIds.length == 0) revert ZeroArrayLength();
    //     if (
    //         baycTokenIds.length != baycAmounts.length || maycTokenIds.length != maycAmounts.length
    //             || bakcTokenIds.length != bakcAmounts.length
    //     ) revert MismatchArrayLength();

    //     uint256 totalDeposit = 0;
    //     for (uint256 i = 0; i < baycTokenIds.length; ++i) {
    //         totalDeposit += baycAmounts[i];
    //     }
    //     for (uint256 i = 0; i < maycTokenIds.length; ++i) {
    //         totalDeposit += maycAmounts[i];
    //     }
    //     for (uint256 i = 0; i < bakcTokenIds.length; ++i) {
    //         totalDeposit += bakcAmounts[i];
    //     }
    //     if (msg.value != totalDeposit) revert InvalidAmount();

    //     if (baycTokenIds.length > 0) _depositNft(_BAYC_POOL_ID, baycTokenIds, baycAmounts);
    //     if (maycTokenIds.length > 0) _depositNft(_MAYC_POOL_ID, maycTokenIds, maycAmounts);
    //     if (bakcTokenIds.length > 0) _depositNft(_BAKC_POOL_ID, bakcTokenIds, bakcAmounts);
    // }

    /**
     * @notice Claim rewards for array of BAYC, MAYC, and BAKC and send to recipient
     * @param baycTokenIds Array of BAYC token IDs
     * @param maycTokenIds Array of MAYC token IDs
     * @param bakcTokenIds Array of BAKC token IDs
     * @param recipient Address to send claim reward to
     */
    // function claimBatch(
    //     uint256[] calldata baycTokenIds,
    //     uint256[] calldata maycTokenIds,
    //     uint256[] calldata bakcTokenIds,
    //     address recipient
    // ) external payable {
    //     if (baycTokenIds.length == 0 && maycTokenIds.length == 0 && bakcTokenIds.length == 0) revert ZeroArrayLength();
    //     if (recipient == address(0)) revert InvalidRecipient();
    //     uint256 valueForFees = msg.value;
    //     if (baycTokenIds.length > 0) {
    //         valueForFees -= _requestClaim(_BAYC_POOL_ID, baycTokenIds, recipient, valueForFees);
    //     }
    //     if (maycTokenIds.length > 0) {
    //         valueForFees -= _requestClaim(_MAYC_POOL_ID, maycTokenIds, recipient, valueForFees);
    //     }
    //     if (bakcTokenIds.length > 0) {
    //         valueForFees -= _requestClaim(_BAKC_POOL_ID, bakcTokenIds, recipient, valueForFees);
    //     }

    //     _refundIfOver(valueForFees);
    // }

    /**
     * @notice Claim rewards for array of BAYC, MAYC, and BAKC
     * @param baycTokenIds Array of BAYC token IDs
     * @param maycTokenIds Array of MAYC token IDs
     * @param bakcTokenIds Array of BAKC token IDs
     */
    // function claimBatchSelf(
    //     uint256[] calldata baycTokenIds,
    //     uint256[] calldata maycTokenIds,
    //     uint256[] calldata bakcTokenIds
    // ) external payable {
    //     if (baycTokenIds.length == 0 && maycTokenIds.length == 0 && bakcTokenIds.length == 0) revert ZeroArrayLength();

    //     uint256 valueForFees = msg.value;
    //     if (baycTokenIds.length > 0) {
    //         valueForFees -= _requestClaim(_BAYC_POOL_ID, baycTokenIds, msg.sender, valueForFees);
    //     }
    //     if (maycTokenIds.length > 0) {
    //         valueForFees -= _requestClaim(_MAYC_POOL_ID, maycTokenIds, msg.sender, valueForFees);
    //     }
    //     if (bakcTokenIds.length > 0) {
    //         valueForFees -= _requestClaim(_BAKC_POOL_ID, bakcTokenIds, msg.sender, valueForFees);
    //     }

    //     _refundIfOver(valueForFees);
    // }

    /**
     * @notice Withdraw staked ApeCoin from the BAYC, MAYC, and BAKC pools.
     * @param baycTokenIds Array of BAYC token IDs
     * @param maycTokenIds Array of MAYC token IDs
     * @param bakcTokenIds Array of BAKC token IDs
     * @param baycAmounts Array of BAYC staked amounts
     * @param maycAmounts Array of MAYC staked amounts
     * @param bakcAmounts Array of BAKC staked amounts
     * @param recipient Address to send withdraw amount and claim to
     */
    // function withdrawBatch(
    //     uint256[] calldata baycTokenIds,
    //     uint256[] calldata maycTokenIds,
    //     uint256[] calldata bakcTokenIds,
    //     uint256[] calldata baycAmounts,
    //     uint256[] calldata maycAmounts,
    //     uint256[] calldata bakcAmounts,
    //     address recipient
    // ) external payable {
    //     if (baycTokenIds.length == 0 && maycTokenIds.length == 0 && bakcTokenIds.length == 0) revert ZeroArrayLength();
    //     if (
    //         baycTokenIds.length != baycAmounts.length || maycTokenIds.length != maycAmounts.length
    //             || bakcTokenIds.length != bakcAmounts.length
    //     ) revert MismatchArrayLength();
    //     if (recipient == address(0)) revert InvalidRecipient();

    //     uint256 valueForFees = msg.value;
    //     if (baycTokenIds.length > 0) {
    //         valueForFees -= _requestWithdraw(_BAYC_POOL_ID, baycTokenIds, baycAmounts, recipient, valueForFees);
    //     }
    //     if (maycTokenIds.length > 0) {
    //         valueForFees -= _requestWithdraw(_MAYC_POOL_ID, maycTokenIds, maycAmounts, recipient, valueForFees);
    //     }
    //     if (bakcTokenIds.length > 0) {
    //         valueForFees -= _requestWithdraw(_BAKC_POOL_ID, bakcTokenIds, bakcAmounts, recipient, valueForFees);
    //     }

    //     _refundIfOver(valueForFees);
    // }

    /**
     * @notice Withdraw staked ApeCoin from the BAYC, MAYC, and BAKC pools.
     * @param baycTokenIds Array of BAYC token IDs
     * @param maycTokenIds Array of MAYC token IDs
     * @param bakcTokenIds Array of BAKC token IDs
     * @param baycAmounts Array of BAYC staked amounts
     * @param maycAmounts Array of MAYC staked amounts
     * @param bakcAmounts Array of BAKC staked amounts
     */
    // function withdrawBatchSelf(
    //     uint256[] calldata baycTokenIds,
    //     uint256[] calldata maycTokenIds,
    //     uint256[] calldata bakcTokenIds,
    //     uint256[] calldata baycAmounts,
    //     uint256[] calldata maycAmounts,
    //     uint256[] calldata bakcAmounts
    // ) external payable {
    //     if (baycTokenIds.length == 0 && maycTokenIds.length == 0 && bakcTokenIds.length == 0) revert ZeroArrayLength();
    //     if (
    //         baycTokenIds.length != baycAmounts.length || maycTokenIds.length != maycAmounts.length
    //             || bakcTokenIds.length != bakcAmounts.length
    //     ) revert MismatchArrayLength();

    //     uint256 valueForFees = msg.value;
    //     if (baycTokenIds.length > 0) {
    //         valueForFees -= _requestWithdraw(_BAYC_POOL_ID, baycTokenIds, baycAmounts, msg.sender, valueForFees);
    //     }
    //     if (maycTokenIds.length > 0) {
    //         valueForFees -= _requestWithdraw(_MAYC_POOL_ID, maycTokenIds, maycAmounts, msg.sender, valueForFees);
    //     }
    //     if (bakcTokenIds.length > 0) {
    //         valueForFees -= _requestWithdraw(_BAKC_POOL_ID, bakcTokenIds, bakcAmounts, msg.sender, valueForFees);
    //     }

    //     _refundIfOver(valueForFees);
    // }

    // Time Range Methods
    /**
     * @notice Add single time range with a given rewards per hour for a given pool
     * @dev In practice one Time Range will represent one quarter (defined by `_startTimestamp`and `_endTimeStamp` as whole hours)
     * where the rewards per hour is constant for a given pool.
     * @param _poolId Available pool values 1-3
     * @param _amount Total amount of ApeCoin to be distributed over the range
     * @param _startTimestamp Whole hour timestamp representation
     * @param _endTimeStamp Whole hour timestamp representation
     * @param _capPerPosition Per position cap amount determined by poolId
     */
    function addTimeRange(
        uint256 _poolId,
        uint256 _amount,
        uint256 _startTimestamp,
        uint256 _endTimeStamp,
        uint256 _capPerPosition
    ) external payable validPool(_poolId) onlyOwner {
        if (msg.value != _amount) revert InvalidAmount();
        if (_startTimestamp >= _endTimeStamp) revert StartGreaterThanEnd();
        if (getMinute(_startTimestamp) > 0 || getSecond(_startTimestamp) > 0) revert StartNotWholeHour();
        if (getMinute(_endTimeStamp) > 0 || getSecond(_endTimeStamp) > 0) revert EndNotWholeHour();

        Pool storage pool = pools[_poolId];
        uint256 length = pool.timeRanges.length;
        if (length > 0) {
            if (_startTimestamp != pool.timeRanges[length - 1].endTimestampHour) revert StartMustEqualLastEnd();
        }

        uint256 hoursInSeconds = _endTimeStamp - _startTimestamp;
        uint256 rewardsPerHour = (_amount * _SECONDS_PER_HOUR) / hoursInSeconds;

        TimeRange memory next = TimeRange(
            _startTimestamp.toUint48(),
            _endTimeStamp.toUint48(),
            rewardsPerHour.toUint96(),
            _capPerPosition.toUint96()
        );
        pool.timeRanges.push(next);

        emit TimeRangeAdded(
            _poolId,
            pool.timeRanges.length - 1,
            _startTimestamp,
            _endTimeStamp,
            rewardsPerHour,
            _capPerPosition
        );
    }

    /**
     * @notice Set the EIDs for the Shadow contract
     * @param eids These EIDs should be all EIDs supported by the Beacon contract
     */
    function setEids(uint32[] calldata eids) external onlyOwner {
        _eids = eids;
    }

    /**
     * @notice Removes the last Time Range for a given pool.
     * @param _poolId Available pool values 1-3
     */
    function removeLastTimeRange(uint256 _poolId) external validPool(_poolId) onlyOwner {
        pools[_poolId].timeRanges.pop();
    }

    /**
     * @notice Execute callback for a pending claim
     * @param guid The GUID of the pending claim
     */
    function executeCallback(bytes32 guid) external {
        PendingClaim storage _claim_ = _pendingClaims[guid];

        uint256 poolId = _claim_.poolId;
        INFTShadow nftShadow = INFTShadow(address(nftContracts[poolId]));
        if (msg.sender != address(nftShadow)) revert Unauthorized();

        // reassemble the uint16map to tokenIds
        uint256 numNfts = _claim_.numNfts;
        uint256[] memory tokenIds = new uint256[](numNfts);
        for (uint256 i = 0; i < numNfts; ++i) {
            tokenIds[i] = uint256(_claim_.tokenIds.get(i));
        }

        if (_claim_.requestType == _CLAIM_TYPE) {
            _claimNft(poolId, tokenIds, _claim_.recipient, _claim_.caller);
        } else {
            uint256[] memory amounts = new uint256[](numNfts);
            for (uint256 i = 0; i < numNfts; ++i) {
                amounts[i] = uint256(_claim_.amounts.get(i));
            }
            _withdraw(poolId, tokenIds, amounts, _claim_.recipient, _claim_.caller);
        }

        emit CallbackExecuted(guid);
    }

    /**
     * @notice Lookup method for a TimeRange struct
     * @return TimeRange A Pool's timeRanges struct by index.
     * @param _poolId Available pool values 1-3
     * @param _index Target index in a Pool's timeRanges array
     */
    function getTimeRangeBy(uint256 _poolId, uint256 _index) public view validPool(_poolId) returns (TimeRange memory) {
        return pools[_poolId].timeRanges[_index];
    }

    // Pool Methods
    /**
     * @notice Lookup available rewards for a pool over a given time range
     * @return uint256 The amount of ApeCoin rewards to be distributed by pool for a given time range
     * @return uint256 The amount of time ranges
     * @param _poolId Available pool values 1-3
     * @param _from Whole hour timestamp representation
     * @param _to Whole hour timestamp representation
     */
    function rewardsBy(
        uint256 _poolId,
        uint256 _from,
        uint256 _to
    ) public view validPool(_poolId) returns (uint256, uint256) {
        Pool memory pool = pools[_poolId];

        uint256 currentIndex = pool.lastRewardsRangeIndex;
        if (_to < pool.timeRanges[0].startTimestampHour) return (0, currentIndex);

        while (
            _from > pool.timeRanges[currentIndex].endTimestampHour &&
            _to > pool.timeRanges[currentIndex].endTimestampHour
        ) {
            unchecked {
                ++currentIndex;
            }
        }

        uint256 rewards;
        TimeRange memory current;
        uint256 startTimestampHour;
        uint256 endTimestampHour;
        uint256 length = pool.timeRanges.length;
        for (uint256 i = currentIndex; i < length; ++i) {
            current = pool.timeRanges[i];
            startTimestampHour = _from <= current.startTimestampHour ? current.startTimestampHour : _from;
            endTimestampHour = _to <= current.endTimestampHour ? _to : current.endTimestampHour;

            rewards = rewards + ((endTimestampHour - startTimestampHour) * current.rewardsPerHour) / _SECONDS_PER_HOUR;

            if (_to <= endTimestampHour) {
                return (rewards, i);
            }
        }

        return (rewards, length - 1);
    }

    /**
     * @notice Updates reward variables `lastRewardedTimestampHour`, `accumulatedRewardsPerShare` and `lastRewardsRangeIndex`
     * for a given pool.
     * @param _poolId Available pool values 1-3
     */
    function updatePool(uint256 _poolId) public validPool(_poolId) {
        Pool storage pool = pools[_poolId];
        if (pool.timeRanges.length == 0) return;

        if (block.timestamp < pool.timeRanges[0].startTimestampHour) return;
        if (block.timestamp <= pool.lastRewardedTimestampHour + _SECONDS_PER_HOUR) return;

        uint48 lastTimestampHour = pool.timeRanges[pool.timeRanges.length - 1].endTimestampHour;
        uint48 previousTimestampHour = getPreviousTimestampHour().toUint48();

        if (pool.stakedAmount == 0) {
            pool.lastRewardedTimestampHour = previousTimestampHour > lastTimestampHour
                ? lastTimestampHour
                : previousTimestampHour;
            return;
        }

        (uint256 rewards, uint256 index) = rewardsBy(_poolId, pool.lastRewardedTimestampHour, previousTimestampHour);
        if (pool.lastRewardsRangeIndex != index) {
            pool.lastRewardsRangeIndex = index.toUint16();
        }
        pool.accumulatedRewardsPerShare = (pool.accumulatedRewardsPerShare +
            (rewards * _APE_COIN_PRECISION) /
            pool.stakedAmount).toUint96();
        pool.lastRewardedTimestampHour = previousTimestampHour > lastTimestampHour
            ? lastTimestampHour
            : previousTimestampHour;

        emit UpdatePool(_poolId, pool.lastRewardedTimestampHour, pool.stakedAmount, pool.accumulatedRewardsPerShare);
    }

    // Read Methods

    function getCurrentTimeRangeIndex(Pool memory pool) private view returns (uint256) {
        uint256 current = pool.lastRewardsRangeIndex;

        if (block.timestamp < pool.timeRanges[current].startTimestampHour) return current;
        for (current = pool.lastRewardsRangeIndex; current < pool.timeRanges.length; ++current) {
            TimeRange memory currentTimeRange = pool.timeRanges[current];
            if (
                currentTimeRange.startTimestampHour <= block.timestamp &&
                block.timestamp <= currentTimeRange.endTimestampHour
            ) return current;
        }
        revert DistributionEnded();
    }

    /**
     * @notice Fetches a PoolUI struct (poolId, stakedAmount, currentTimeRange) for each reward pool
     * @return PoolUI for BAYC.
     * @return PoolUI for MAYC.
     * @return PoolUI for BAKC.
     */
    function getPoolsUI() external view returns (PoolUI memory, PoolUI memory, PoolUI memory) {
        Pool memory baycPool = pools[1];
        Pool memory maycPool = pools[2];
        Pool memory bakcPool = pools[3];
        uint256 current = getCurrentTimeRangeIndex(baycPool);
        return (
            PoolUI(1, baycPool.stakedAmount, baycPool.timeRanges[current]),
            PoolUI(2, maycPool.stakedAmount, maycPool.timeRanges[current]),
            PoolUI(3, bakcPool.stakedAmount, bakcPool.timeRanges[current])
        );
    }

    /**
     * @notice Fetches an address total staked amount, used by voting contract
     * @param baycTokenIds An array of BAYC token ids
     * @param maycTokenIds An array of MAYC token ids
     * @param bakcTokenIds An array of BAKC token ids
     * @return total uint256 staked amount for all pools.
     */
    function stakedTotal(
        uint256[] memory baycTokenIds,
        uint256[] memory maycTokenIds,
        uint256[] memory bakcTokenIds
    ) external view returns (uint256 total) {
        total += _stakedTotal(_BAYC_POOL_ID, baycTokenIds);
        total += _stakedTotal(_MAYC_POOL_ID, maycTokenIds);
        total += _stakedTotal(_BAKC_POOL_ID, bakcTokenIds);

        return total;
    }

    function _stakedTotal(uint256 _poolId, uint256[] memory tokenIds) private view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            total += nftPosition[_poolId][tokenId].stakedAmount;
        }

        return total;
    }

    /**
     * @notice Fetches a DashboardStake = [poolId, tokenId, deposited, unclaimed, rewards24Hrs] \
     * for each pool, for an Ethereum address
     * @return dashboardStakes An array of DashboardStake structs
     * @param _address An Ethereum address
     */
    function getAllStakes(
        address _address,
        uint256[] calldata baycTokenIds,
        uint256[] calldata maycTokenIds,
        uint256[] calldata bakcTokenIds
    ) external view returns (DashboardStake[] memory) {
        DashboardStake[] memory baycStakes = _getStakes(_address, _BAYC_POOL_ID, baycTokenIds);
        DashboardStake[] memory maycStakes = _getStakes(_address, _MAYC_POOL_ID, maycTokenIds);
        DashboardStake[] memory bakcStakes = _getStakes(_address, _BAKC_POOL_ID, bakcTokenIds);

        uint256 count = (baycStakes.length + maycStakes.length + bakcStakes.length);
        DashboardStake[] memory allStakes = new DashboardStake[](count);

        uint256 offset;

        for (uint256 i = 0; i < baycStakes.length; ++i) {
            allStakes[offset] = baycStakes[i];
            ++offset;
        }

        for (uint256 i = 0; i < maycStakes.length; ++i) {
            allStakes[offset] = maycStakes[i];
            ++offset;
        }

        for (uint256 i = 0; i < bakcStakes.length; ++i) {
            allStakes[offset] = bakcStakes[i];
            ++offset;
        }

        return allStakes;
    }

    /**
     * @notice Fetches an array of DashboardStakes for the BAYC pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getBaycStakes(
        address _address,
        uint256[] memory tokenIds
    ) external view returns (DashboardStake[] memory) {
        return _getStakes(_address, _BAYC_POOL_ID, tokenIds);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the MAYC pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getMaycStakes(
        address _address,
        uint256[] memory tokenIds
    ) external view returns (DashboardStake[] memory) {
        return _getStakes(_address, _MAYC_POOL_ID, tokenIds);
    }

    /**
     * @notice Fetches an array of DashboardStakes for the BAKC pool
     * @return dashboardStakes An array of DashboardStake structs
     */
    function getBakcStakes(
        address _address,
        uint256[] memory tokenIds
    ) external view returns (DashboardStake[] memory) {
        return _getStakes(_address, _BAKC_POOL_ID, tokenIds);
    }

    function _getStakes(
        address _address,
        uint256 _poolId,
        uint256[] memory tokenIds
    ) private view returns (DashboardStake[] memory) {
        DashboardStake[] memory dashboardStakes = new DashboardStake[](tokenIds.length);
        uint256 validStakeCount = 0;

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            // Verify ownership
            if (nftContracts[_poolId].ownerOf(tokenId) == _address) {
                uint256 deposited = nftPosition[_poolId][tokenId].stakedAmount;
                uint256 unclaimed = deposited > 0 ? this.pendingRewards(_poolId, tokenId) : 0;
                uint256 rewards24Hrs = deposited > 0 ? _estimate24HourRewards(_poolId, tokenId) : 0;

                if (deposited > 0 || unclaimed > 0) {
                    dashboardStakes[validStakeCount] = DashboardStake(
                        _poolId,
                        tokenId,
                        deposited,
                        unclaimed,
                        rewards24Hrs
                    );
                    validStakeCount++;
                }
            }
        }

        // Resize array if needed
        if (validStakeCount < tokenIds.length) {
            DashboardStake[] memory resizedStakes = new DashboardStake[](validStakeCount);
            for (uint256 i = 0; i < validStakeCount; ++i) {
                resizedStakes[i] = dashboardStakes[i];
            }
            return resizedStakes;
        }

        return dashboardStakes;
    }

    function _estimate24HourRewards(uint256 _poolId, uint256 _tokenId) private view returns (uint256) {
        Pool memory pool = pools[_poolId];
        Position memory position = nftPosition[_poolId][_tokenId];

        TimeRange memory rewards = getTimeRangeBy(_poolId, pool.lastRewardsRangeIndex);
        return (position.stakedAmount * uint256(rewards.rewardsPerHour) * 24) / uint256(pool.stakedAmount);
    }

    /**
     * @notice Fetches the current amount of claimable ApeCoin rewards for a given position from a given pool.
     * @return uint256 value of pending rewards
     * @param _poolId Available pool values 1-3
     * @param _tokenId An NFT id
     */
    function pendingRewards(uint256 _poolId, uint256 _tokenId) external view returns (uint256) {
        Pool memory pool = pools[_poolId];
        Position memory position = nftPosition[_poolId][_tokenId];

        (uint256 rewardsSinceLastCalculated, ) = rewardsBy(
            _poolId,
            pool.lastRewardedTimestampHour,
            getPreviousTimestampHour()
        );
        uint256 accumulatedRewardsPerShare = pool.accumulatedRewardsPerShare;

        if (block.timestamp > pool.lastRewardedTimestampHour + _SECONDS_PER_HOUR && pool.stakedAmount != 0) {
            accumulatedRewardsPerShare =
                accumulatedRewardsPerShare +
                (rewardsSinceLastCalculated * _APE_COIN_PRECISION) /
                pool.stakedAmount;
        }
        return
            ((position.stakedAmount * accumulatedRewardsPerShare).toInt256() - position.rewardsDebt).toUint256() /
            _APE_COIN_PRECISION;
    }

    /**
     * @notice Fetches the LZ fee for a request to read a batch of NFTs from all pools.
     * @return fee uint256 fee for the request
     * @param baycTokenIds An array of BAYC token ids
     * @param maycTokenIds An array of MAYC token ids
     * @param bakcTokenIds An array of BAKC token ids
     */
    function quoteRequestBatch(
        uint256[] calldata baycTokenIds,
        uint256[] calldata maycTokenIds,
        uint256[] calldata bakcTokenIds
    ) external view returns (uint256 fee) {
        unchecked {
            fee += quoteRequest(_BAYC_POOL_ID, baycTokenIds);
            fee += quoteRequest(_MAYC_POOL_ID, maycTokenIds);
            fee += quoteRequest(_BAKC_POOL_ID, bakcTokenIds);
        }

        return fee;
    }

    /**
     * @notice Fetches a PendingClaim struct for a given guid
     * @return poolId uint8 poolId
     * @return requestType uint8 requestType
     * @return caller address caller
     * @return recipient address recipient
     * @return numNfts uint96 numNfts
     * @param guid bytes32 guid
     */
    function pendingClaims(
        bytes32 guid
    ) external view returns (uint8 poolId, uint8 requestType, address caller, address recipient, uint96 numNfts) {
        return (
            _pendingClaims[guid].poolId,
            _pendingClaims[guid].requestType,
            _pendingClaims[guid].caller,
            _pendingClaims[guid].recipient,
            _pendingClaims[guid].numNfts
        );
    }

    /**
     * @notice Fetches the LZ fee for a request to read a batch of NFTs from a given pool.
     * @param poolId Available pool values 1-3
     * @param tokenIds An array of NFT ids
     * @return fee uint256 fee for the request
     */
    function quoteRequest(uint256 poolId, uint256[] calldata tokenIds) public view returns (uint256 fee) {
        if (tokenIds.length == 0) return 0;

        INFTShadow shadowContract = nftContracts[poolId];
        (uint256[] memory lockedNfts, ) = _splitNfts(shadowContract, tokenIds);
        if (lockedNfts.length == 0) return 0;

        uint128 callbackGasLimit = _BASE_CALLBACK_GAS_LIMIT +
            _INCREMENTAL_CALLBACK_GAS_LIMIT *
            uint128(lockedNfts.length);

        // base collection address for BAYC, MAYC, BAKC are same as shadows
        (uint256 nativeFee, ) = _beacon.quoteRead(address(shadowContract), tokenIds, _eids, callbackGasLimit);
        return nativeFee;
    }

    // Convenience methods for timestamp calculation
    /// @notice the minutes (0 to 59) of a timestamp
    function getMinute(uint256 timestamp) internal pure returns (uint256 minute) {
        uint256 secs = timestamp % _SECONDS_PER_HOUR;
        minute = secs / _SECONDS_PER_MINUTE;
    }

    /// @notice the seconds (0 to 59) of a timestamp
    function getSecond(uint256 timestamp) internal pure returns (uint256 second) {
        second = timestamp % _SECONDS_PER_MINUTE;
    }

    /// @notice the previous whole hour of a timestamp
    function getPreviousTimestampHour() internal view returns (uint256) {
        return block.timestamp - (getMinute(block.timestamp) * 60 + getSecond(block.timestamp));
    }

    // Private Methods - shared logic
    function _deposit(uint256 _poolId, Position storage _position, uint256 _amount) private {
        Pool storage pool = pools[_poolId];

        _position.stakedAmount += _amount;
        pool.stakedAmount += _amount.toUint96();
        _position.rewardsDebt += (_amount * pool.accumulatedRewardsPerShare).toInt256();
    }

    function _depositNft(uint256 _poolId, uint256[] calldata _tokenIds, uint256[] calldata _amounts) private {
        updatePool(_poolId);
        Position storage position;
        uint256 length = _tokenIds.length;
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = _tokenIds[i];
            position = nftPosition[_poolId][tokenId];
            if (position.stakedAmount == 0) {
                if (nftContracts[_poolId].ownerOf(tokenId) != msg.sender) revert CallerNotOwner();
            }
            uint256 amount = _amounts[i];
            _depositNftGuard(_poolId, position, amount);
            emit Deposit(msg.sender, _poolId, amount, tokenId);
        }
    }

    function _depositNftGuard(uint256 _poolId, Position storage _position, uint256 _amount) private {
        if (_amount < _MIN_DEPOSIT) revert DepositMoreThanOneAPE();
        if (
            _amount + _position.stakedAmount >
            pools[_poolId].timeRanges[pools[_poolId].lastRewardsRangeIndex].capPerPosition
        ) {
            revert ExceededCapAmount();
        }

        _deposit(_poolId, _position, _amount);
    }

    function _claim(
        uint256 _poolId,
        Position storage _position,
        address _recipient
    ) private returns (uint256 rewardsToBeClaimed) {
        Pool storage pool = pools[_poolId];

        int256 accumulatedApeCoins = (_position.stakedAmount * uint256(pool.accumulatedRewardsPerShare)).toInt256();
        rewardsToBeClaimed = (accumulatedApeCoins - _position.rewardsDebt).toUint256() / _APE_COIN_PRECISION;

        _position.rewardsDebt = accumulatedApeCoins;

        if (rewardsToBeClaimed != 0) {
            (bool success, ) = _recipient.call{value: rewardsToBeClaimed}("");
            if (!success) revert TransferFailed();
        }
    }

    function _requestClaim(
        uint256 _poolId,
        uint256[] calldata _nfts,
        address _recipient,
        uint256 valueForFees
    ) private returns (uint256 fee) {
        // pass _nfts a second time in place of amounts, it gets ignored in the claim context
        fee = _request(_poolId, _nfts, _nfts, _recipient, _CLAIM_TYPE, valueForFees);
    }

    function _requestWithdraw(
        uint256 _poolId,
        uint256[] calldata _tokenIds,
        uint256[] calldata _amounts,
        address _recipient,
        uint256 valueForFees
    ) private returns (uint256 fee) {
        fee = _request(_poolId, _tokenIds, _amounts, _recipient, _WITHDRAW_TYPE, valueForFees);
    }

    function _request(
        uint256 _poolId,
        uint256[] calldata _tokenIds,
        uint256[] calldata _amounts,
        address _recipient,
        uint8 _type,
        uint256 valueForFees
    ) private returns (uint256 fee) {
        INFTShadow _shadowContract = nftContracts[_poolId];

        (uint256[] memory lockedNfts, uint256[] memory unlockedNfts) = _splitNfts(_shadowContract, _tokenIds);

        uint256 lockedNftsCount = lockedNfts.length;
        if (lockedNftsCount > 0) {
            uint128 callbackGasLimit = _BASE_CALLBACK_GAS_LIMIT +
                _INCREMENTAL_CALLBACK_GAS_LIMIT *
                uint128(lockedNftsCount);
            (fee, ) = _beacon.quoteRead(address(_shadowContract), lockedNfts, _eids, callbackGasLimit);
            if (valueForFees < fee) revert InsufficientFee();

            bytes32 guid = _shadowContract.readWithCallback{value: fee}(lockedNfts, _eids, callbackGasLimit);

            _pendingClaims[guid].poolId = uint8(_poolId);
            _pendingClaims[guid].requestType = _type;
            _pendingClaims[guid].recipient = _recipient;
            _pendingClaims[guid].numNfts = uint96(lockedNftsCount);
            _pendingClaims[guid].caller = msg.sender;

            for (uint256 i; i < lockedNftsCount; ++i) {
                _pendingClaims[guid].tokenIds.set(i, lockedNfts[i].toUint16());
                if (_type == _WITHDRAW_TYPE) {
                    _pendingClaims[guid].amounts.set(i, _amounts[i].toUint128());
                }
            }

            emit RequestSubmitted(guid, msg.sender, uint8(_poolId), _type, lockedNfts, _recipient);
        }

        if (unlockedNfts.length > 0) {
            if (_type == _CLAIM_TYPE) {
                _claimNft(_poolId, unlockedNfts, _recipient, msg.sender);
            } else if (_type == _WITHDRAW_TYPE) {
                _withdraw(_poolId, unlockedNfts, _amounts, _recipient, msg.sender);
            }
        }
    }

    function _splitNfts(
        INFTShadow _shadowContract,
        uint256[] memory _tokenIds
    ) private view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory lockedNftsRaw = new uint256[](_tokenIds.length);
        uint256[] memory unlockedNftsRaw = new uint256[](_tokenIds.length);
        uint256 lockedNftsCount = 0;
        uint256 unlockedNftsCount = 0;

        for (uint256 i; i < _tokenIds.length; ++i) {
            if (_shadowContract.locked(_tokenIds[i])) {
                lockedNftsRaw[lockedNftsCount] = _tokenIds[i];
                unchecked {
                    ++lockedNftsCount;
                }
            } else {
                unlockedNftsRaw[unlockedNftsCount] = _tokenIds[i];
                unchecked {
                    ++unlockedNftsCount;
                }
            }
        }

        // resize arrays
        uint256[] memory lockedNfts = new uint256[](lockedNftsCount);
        uint256[] memory unlockedNfts = new uint256[](unlockedNftsCount);

        for (uint256 i; i < lockedNftsCount; ++i) {
            lockedNfts[i] = lockedNftsRaw[i];
        }
        for (uint256 i; i < unlockedNftsCount; ++i) {
            unlockedNfts[i] = unlockedNftsRaw[i];
        }

        return (lockedNfts, unlockedNfts);
    }

    function _claimNft(uint256 _poolId, uint256[] memory _tokenIds, address _recipient, address _caller) private {
        updatePool(_poolId);

        INFTShadow shadowContract = nftContracts[_poolId];

        for (uint256 i; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            if (shadowContract.ownerOf(tokenId) != _caller) revert CallerNotOwner();

            Position storage position = nftPosition[_poolId][tokenId];
            uint256 rewardsToBeClaimed = _claim(_poolId, position, _recipient);

            emit Claim(_caller, _poolId, rewardsToBeClaimed, tokenId);
        }
    }

    function _withdraw(
        uint256 _poolId,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts,
        address _recipient,
        address _caller
    ) private {
        updatePool(_poolId);
        uint256 tokenId;
        uint256 amount;
        uint256 length = _tokenIds.length;
        uint256 totalWithdraw;
        Position storage position;
        for (uint256 i; i < length; ++i) {
            tokenId = _tokenIds[i];
            if (nftContracts[_poolId].ownerOf(tokenId) != _caller) revert CallerNotOwner();

            amount = _amounts[i];
            position = nftPosition[_poolId][tokenId];
            if (amount == position.stakedAmount) {
                uint256 rewardsToBeClaimed = _claim(_poolId, position, _recipient);
                emit Claim(_caller, _poolId, rewardsToBeClaimed, tokenId);
            }

            if (amount > position.stakedAmount) revert ExceededStakedAmount();

            Pool storage pool = pools[_poolId];

            unchecked {
                position.stakedAmount -= amount;
                pool.stakedAmount -= amount.toUint96();
                position.rewardsDebt -= (amount * pool.accumulatedRewardsPerShare).toInt256();

                totalWithdraw += amount;
            }

            emit Withdraw(_caller, _poolId, amount, _recipient, tokenId);
        }

        if (totalWithdraw > 0) {
            (bool success, ) = _recipient.call{value: totalWithdraw}("");
            if (!success) revert WithdrawFailed();
        }
    }

    function _refundIfOver(uint256 valueForFees) private {
        if (valueForFees > 0) {
            (bool success, ) = msg.sender.call{value: valueForFees}("");
            if (!success) revert RefundFailed();
        }
    }
}
