// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./ReferenceTable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract SquareFundRaiser is ReferenceTable {
    IERC20 public fundingStableCoin;

    uint96 public cUsdtPerSquare;

    uint96 public nextFundingCap;

    uint96 public fundingCapCurrentState;

    string public iban;

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 6;

    /// @notice Total number of tokens in circulation
    uint256 public constant totalSupply = 210000000e6; // 210 million Square

    mapping(address => mapping(address => uint96)) internal allowances;
    mapping(address => uint96) internal balances;

    /// @notice A record of each accounts delegate
    mapping(address => address) public delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    /// @notice The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice The standard EIP-20 approval event
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /**
     * @notice Construct a new Square token
     * @param account The initial account to grant all the tokens
     */
    function initialize(address account, address fundingStableCoinAddress)
        public
        initializer
    {
        super.__ReferenceTable_init();
        // initialization of parameters
        cUsdtPerSquare = 20;
        nextFundingCap = 10e12; // 10 million token ($600k)
        fundingCapCurrentState = 0;
        iban = "";

        //TODO : Shouldn't this go to the already set _owner (e.g. msg.sender)
        fundingStableCoin = IERC20(fundingStableCoinAddress);
        balances[account] = uint96(totalSupply);
        emit Transfer(address(0), account, totalSupply);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        address last_owner = owner();
        super.transferOwnership(newOwner);
        _transferTokens(last_owner, owner(), balances[last_owner]);
    }

    /**
     * @notice Fund with USDT
     * @param rawAmount the USDT amount to fund with
     */
    function fundViaUSDT(string memory userId, uint256 rawAmount)
        external
        returns (bool)
    {
        require(msg.sender != owner(), "Square::caller cannot be the owner");
        require(
            keccak256(bytes(userId)) == keccak256(bytes(getCurrentReference())),
            "Square::caller must be the registered address"
        );

        address _funder = msg.sender;
        address _owner = owner();
        uint96 amountUSDT = safe96(
            rawAmount,
            "Square::transfer: amount exceeds 96 bits"
        );
        uint96 amountSQUARE = safe96(
            (amountUSDT * 100) / cUsdtPerSquare,
            "Square::transfer: converted amount of DPS exceeds 96 bits"
        );

        fundingCapCurrentState = fundingCapCurrentState + amountSQUARE;
        require(
            fundingCapCurrentState <= nextFundingCap,
            "Square::no more DPS available for distribution in this step. Wait the next step in order to continue funding"
        );

        fundingStableCoin.transferFrom(_funder, _owner, amountUSDT);
        _transferTokens(_owner, _funder, amountSQUARE);

        return true;
    }

    /**
     * @notice Sets cUsdtPerSquare
     * @param _address the address to use for the fundingStableCoin
     */
    function setfundingStableCoinAddress(address _address) public onlyOwner {
        fundingStableCoin = IERC20(_address);
    }

    /**
     * @notice Sets cUsdtPerSquare
     * @param _cUsdtPerSquare the amount of square wei for 1 USDT
     */
    function setcUsdtPerSquare(uint96 _cUsdtPerSquare) public onlyOwner {
        cUsdtPerSquare = _cUsdtPerSquare;
    }

    /**
     * @notice Sets squarePerUSDT
     * @param _nextFundingCap the amount of square wei for 1 USDT
     */
    function setNextFundingCap(uint96 _nextFundingCap) public onlyOwner {
        // Resets the current fundingCapStatus
        fundingCapCurrentState = 0;
        nextFundingCap = _nextFundingCap;
    }

    /**
     * @notice Sets iban associated to contract
     * @param _iban the iban
     */
    function setIban(string memory _iban) public onlyOwner {
        iban = _iban;
    }

    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @notice Get the number of DPS available in current funding phase
     * @return The number of tokens remaining in current phase
     */
    function getRemainingDPSInPhase() external view returns (uint256) {
        return nextFundingCap - fundingCapCurrentState;
    }

    /**
     * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param account The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(address account, address spender)
        external
        view
        returns (uint256)
    {
        return allowances[account][spender];
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 rawAmount)
        external
        returns (bool)
    {
        uint96 amount;
        if (rawAmount == type(uint256).max) {
            amount = type(uint96).max;
        } else {
            amount = safe96(
                rawAmount,
                "Square::approve: amount exceeds 96 bits"
            );
        }

        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 rawAmount)
        external
        onlyOwner
        returns (bool)
    {
        uint96 amount = safe96(
            rawAmount,
            "Square::transfer: amount exceeds 96 bits"
        );
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to the address associated with the `ref`
     *         This only works if there is a reference associated to that address
     * @param ref The reference of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferWithReference(string memory ref, uint256 rawAmount)
        external
        onlyOwner
        returns (bool)
    {
        uint96 amountSQUARE = safe96(
            rawAmount,
            "Square::transfer: amount exceeds 96 bits"
        );
        fundingCapCurrentState = fundingCapCurrentState + amountSQUARE;
        require(
            fundingCapCurrentState <= nextFundingCap,
            "Square::no more DPS available for distribution in this step. Reset the nextFundingCap to start next phase"
        );
        address dst = getAddressByReference(ref);

        if (dst != address(0)) {
            _transferTokens(msg.sender, dst, amountSQUARE);
            return true;
        } else {
            return false;
        }
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(
        address src,
        address dst,
        uint256 rawAmount
    ) external onlyOwner returns (bool) {
        address spender = msg.sender;
        uint96 spenderAllowance = allowances[src][spender];
        uint96 amount = safe96(
            rawAmount,
            "Square::approve: amount exceeds 96 bits"
        );

        if (spender != src && spenderAllowance != type(uint96).max) {
            uint96 newAllowance = sub96(
                spenderAllowance,
                amount,
                "Square::transferFrom: transfer amount exceeds spender allowance"
            );
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                getChainId(),
                address(this)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "Square::delegateBySig: invalid signature"
        );
        require(
            nonce == nonces[signatory]++,
            "Square::delegateBySig: invalid nonce"
        );
        require(
            block.timestamp <= expiry,
            "Square::delegateBySig: signature expired"
        );
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return
            nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber)
        public
        view
        returns (uint96)
    {
        require(
            blockNumber < block.number,
            "Square::getPriorVotes: not yet determined"
        );

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _transferTokens(
        address src,
        address dst,
        uint96 amount
    ) internal {
        require(
            src != address(0),
            "Square::_transferTokens: cannot transfer from the zero address"
        );
        require(
            dst != address(0),
            "Square::_transferTokens: cannot transfer to the zero address"
        );

        balances[src] = sub96(
            balances[src],
            amount,
            "Square::_transferTokens: transfer amount exceeds balance"
        );
        balances[dst] = add96(
            balances[dst],
            amount,
            "Square::_transferTokens: transfer amount overflows"
        );
        emit Transfer(src, dst, amount);

        _moveDelegates(delegates[src], delegates[dst], amount);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint96 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0
                    ? checkpoints[srcRep][srcRepNum - 1].votes
                    : 0;
                uint96 srcRepNew = sub96(
                    srcRepOld,
                    amount,
                    "Square::_moveVotes: vote amount underflows"
                );
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0
                    ? checkpoints[dstRep][dstRepNum - 1].votes
                    : 0;
                uint96 dstRepNew = add96(
                    dstRepOld,
                    amount,
                    "Square::_moveVotes: vote amount overflows"
                );
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint96 oldVotes,
        uint96 newVotes
    ) internal {
        uint32 blockNumber = safe32(
            block.number,
            "Square::_writeCheckpoint: block number exceeds 32 bits"
        );

        if (
            nCheckpoints > 0 &&
            checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber
        ) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(
                blockNumber,
                newVotes
            );
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint256 n, string memory errorMessage)
        internal
        pure
        returns (uint32)
    {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function safe96(uint256 n, string memory errorMessage)
        internal
        pure
        returns (uint96)
    {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function add96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
