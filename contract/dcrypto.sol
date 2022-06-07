// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";


contract Dcrypto is Initializable, UUPSUpgradeable, ERC20Upgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IERC20Upgradeable public crypto;

    //highest staked users
    struct HighestAstaStaker {
        uint256 deposited;
        address addr;
    }
    mapping(uint256 => HighestAstaStaker[]) public highestStakerInPool;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardCRYPTODebt;

    }

    // Info of each pool.
    struct PoolInfo {
        IERC20Upgradeable lpToken;           // Address of LP token contract.
        uint256 allocPoint;      
        uint256 lastRewardBlock;    
        uint256 accCRYPTOPerShare;    //CRYPTO
        uint256 lastTotalCRYPTOReward;    
        uint256 lastCRYPTORewardBalance;  
        uint256 totalCRYPTOReward;    
    }

    // The CRYPTO TOKEN!
    IERC20Upgradeable public CRYPTO;
    // admin address.
    address public adminAddress;
    // Bonus muliplier for early CRYPTO makers.
    uint256 public constant BONUS_MULTIPLIER = 1;

    // Number of top staker stored

    uint256 public topStakerNumber;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when reward distribution start.
    uint256 public startBlock;
    // total CRYPTO staked
    uint256 public totalCRYPTOStaked;
    // total CRYPTO used for purchase land
    uint256 public totalCryptoUsedForPurchase;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event AdminUpdated(address newAdmin);

    function initialize(        
        IERC20Upgradeable _crypto,
        address _adminAddress,
        uint256 _startBlock,
        uint256 _topStakerNumber
        ) public initializer {
        require(_adminAddress != address(0), "initialize: Zero address");
        OwnableUpgradeable.__Ownable_init();
        __ERC20_init_unchained("dCRYPTO", "dCRYPTO");
        __Pausable_init_unchained();
        ERC20PermitUpgradeable.__ERC20Permit_init("dCRYPTO");
        ERC20VotesUpgradeable.__ERC20Votes_init_unchained();
        CRYPTO = _crypto;
        adminAddress = _adminAddress;
        startBlock = _startBlock;
        topStakerNumber = _topStakerNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20Upgradeable _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accCRYPTOPerShare: 0,
            lastTotalCRYPTOReward: 0,
            lastCRYPTORewardBalance: 0,
            totalCRYPTOReward: 0
        }));
    }

    // Update the given pool's CRYPTO allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }
    
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        if (_to >= _from) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else {
            return _from.sub(_to);
        }
    }
    
    // View function to see pending CRYPTOs on frontend.
    function pendingCRYPTO(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCRYPTOPerShare = pool.accCRYPTOPerShare;
        uint256 lpSupply = totalCRYPTOStaked;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 rewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalCRYPTOStaked.sub(totalCRYPTOUsedForPurchase));
            uint256 _totalReward = rewardBalance.sub(pool.lastCRYPTORewardBalance);
            accCRYPTOPerShare = accCRYPTOPerShare.add(_totalReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accCRYPTOPerShare).div(1e12).sub(user.rewardCRYPTODebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 rewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalCRYPTOStaked.sub(totalCryptoUsedForPurchase));
        uint256 _totalReward = pool.totalCRYPTOReward.add(rewardBalance.sub(pool.lastCRYPTORewardBalance));
        pool.lastCRYPTORewardBalance = rewardBalance;
        pool.totalCRYPTOReward = _totalReward;
        
        uint256 lpSupply = totalCRYPTOStaked;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            pool.accCRYPTOPerShare = 0;
            pool.lastTotalCRYPTOReward = 0;
            user.rewardCRYPTODebt = 0;
            pool.lastCRYPTORewardBalance = 0;
            pool.totalCRYPTOReward = 0;
            return;
        }
        
        uint256 reward = _totalReward.sub(pool.lastTotalCRYPTOReward);
        pool.accCRYPTOPerShare = pool.accCRYPTOPerShare.add(reward.mul(1e12).div(lpSupply));
        pool.lastTotalCRYPTOReward = _totalReward;
    }

    /**
    @notice Sorting the highest CRYPTO staker in pool
    @param _pid : pool id
    @param left : left
    @param right : right
    @dev Description :
        It is used for sorting the highest CRYPTO staker in pool. This function definition is marked
        "internal" because this function is called only from inside the contract.
    */
    function quickSort(
        uint256 _pid,
        uint256 left,
        uint256 right
    ) internal {
        HighestAstaStaker[] storage arr = highestStakerInPool[_pid];
        if (left >= right) return;
        uint256 divtwo = 2;
        uint256 p = arr[(left + right) / divtwo].deposited; // p = the pivot element
        uint256 i = left;
        uint256 j = right;
        while (i < j) {
            // HighestAstaStaker memory a;
            // HighestAstaStaker memory b;
            while (arr[i].deposited < p) ++i;
            while (arr[j].deposited > p) --j; // arr[j] > p means p still to the left, so j > 0
            if (arr[i].deposited > arr[j].deposited) {
                (arr[i].deposited, arr[j].deposited) = (
                    arr[j].deposited,
                    arr[i].deposited
                );
                (arr[i].addr, arr[j].addr) = (arr[j].addr, arr[i].addr);
            } else ++i;
        }
        // Note --j was only done when a[j] > p.  So we know: a[j] == p, a[<j] <= p, a[>j] > p
        if (j > left) quickSort(_pid, left, j - 1); // j > left, so j > 0
        quickSort(_pid, j + 1, right);
    }
    /**
    @notice store Highest 50 staked users
    @param _pid : pool id
    @param _amount : amount
    @dev Description :
    DAO governance will be performed by the top 50 wallets with the highest amount of staked CRYPTO tokens.
    */
    function addHighestStakedUser(
        uint256 _pid,
        uint256 _amount,
        address user
    ) private {
        uint256 i;
        // Getting the array of Highest staker as per pool id.
        HighestAstaStaker[] storage highestStaker = highestStakerInPool[_pid];
        //for loop to check if the staking address exist in array
        for (i = 0; i < highestStaker.length; i++) {
            if (highestStaker[i].addr == user) {
                highestStaker[i].deposited = _amount;
                // Called the function for sorting the array in ascending order.
                quickSort(_pid, 0, highestStaker.length - 1);
                return;
            }
        }

        if (highestStaker.length < topStakerNumber) {
            // Here if length of highest staker is less than 100 than we just push the object into array.
            highestStaker.push(HighestAstaStaker(_amount, user));
        } else {
            // Otherwise we check the last staker amount in the array with new one.
            if (highestStaker[0].deposited < _amount) {
                // If the last staker deposited amount is less than new then we put the greater one in the array.
                highestStaker[0].deposited = _amount;
                highestStaker[0].addr = user;
            }
        }
        // Called the function for sorting the array in ascending order.
        quickSort(_pid, 0, highestStaker.length - 1);
    }

    /**
    @notice CRYPTO staking track the Highest 50 staked users
    @param _pid : pool id
    @param user : user address
    @dev Description :
    DAO governance will be performed by the top 50 wallets with the highest amount of staked CRYPTO tokens. 
    */
    function checkHighestStaker(uint256 _pid, address user)
        public
        view
        returns (bool)
    {
        HighestAstaStaker[] storage highestStaker = highestStakerInPool[_pid];
        uint256 i = 0;
        // Applied the loop to check the user in the highest staker list.
        for (i; i < highestStaker.length; i++) {
            if (highestStaker[i].addr == user) {
                // If user is exists in the list then we return true otherwise false.
                return true;
            }
        }
    }

    // Deposit CRYPTO tokens to MasterChef.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {

            uint256 cryptoReward = user.amount.mul(pool.accCRYPTOPerShare).div(1e12).sub(user.rewardCRYPTODebt);
            pool.lpToken.safeTransfer(msg.sender, cryptoReward);
            pool.lastCRYPTORewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalCRYPTOStaked.sub(totalCRYPTOUsedForPurchase));
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        totalCRYPTOStaked = totalCRYPTOStaked.add(_amount);
        user.amount = user.amount.add(_amount);
        user.rewardCRYPTODebt = user.amount.mul(pool.accCRYPTOPerShare).div(1e12);
        addHighestStakedUser(_pid, user.amount, msg.sender);
        _mint(msg.sender,_amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);

        uint256 cryptoReward = user.amount.mul(pool.accCRYPTOPerShare).div(1e12).sub(user.rewardCRYPTODebt);
        pool.lpToken.safeTransfer(msg.sender, cryptoReward);
        pool.lastCRYPTORewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalCRYPTOStaked.sub(totalCryptoUsedForPurchase));

        user.amount = user.amount.sub(_amount);
        totalCRYPTOStaked = totalCRYPTOStaked.sub(_amount);
        user.rewardCRYPTODebt = user.amount.mul(pool.accCRYPTOPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        removeHighestStakedUser(_pid, user.amount, msg.sender);
        _burn(msg.sender,_amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Update the staker details in case of withdrawal
    function removeHighestStakedUser(uint256 _pid, uint256 _amount, address user) private {
        // Getting Highest staker list as per the pool id
        HighestAstaStaker[] storage highestStaker = highestStakerInPool[_pid];
        // Applied this loop is just to find the staker
        for (uint256 i = 0; i < highestStaker.length; i++) {
            if (highestStaker[i].addr == user) {
                // Deleting the staker from the array.
                delete highestStaker[i];
                if(_amount > 0) {
                    // If amount is greater than 0 than we need to add this again in the highest staker list.
                    addHighestStakedUser(_pid, _amount, user);
                }
                return;
            }
        }
    }

    
    // Earn CRYPTO tokens to MasterChef.
    function claimCRYPTO(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        
        uint256 cryptoReward = user.amount.mul(pool.accCRYPTOPerShare).div(1e12).sub(user.rewardCRYPTODebt);
        pool.lpToken.safeTransfer(msg.sender, cryptoReward);
        pool.lastCRYPTORewardBalance = pool.lpToken.balanceOf(address(this)).sub(totalCRYPTOStaked.sub(totalCryptoUsedForPurchase));
        
        user.rewardCRYPTODebt = user.amount.mul(pool.accCRYPTOPerShare).div(1e12);
    }
    
    // Safe CRYPTO transfer function to admin.
    function accessCRYPTOTokens(uint256 _pid, address _to, uint256 _amount) public {
        require(msg.sender == adminAddress, "sender must be admin address");
        require(totalCRYPTOStaked.sub(totalCryptoUsedForPurchase) >= _amount, "Amount must be less than staked CRYPTO amount");
        PoolInfo storage pool = poolInfo[_pid];
        uint256 CryptoBal = pool.lpToken.balanceOf(address(this));
        if (_amount > CryptoBal) {
            pool.lpToken.transfer(_to, CryptoBal);
            totalCryptoUsedForPurchase = totalCryptoUsedForPurchase.add(CryptoBal);
            emit EmergencyWithdraw(_to, _pid, CryptoBal);
        } else {
            pool.lpToken.transfer(_to, _amount);
            totalCryptoUsedForPurchase = totalCryptoUsedForPurchase.add(_amount);
            emit EmergencyWithdraw(_to, _pid, _amount);
        }
    }
    // Update admin address by the previous admin.
    function admin(address _adminAddress) public {
        require(_adminAddress != address(0), "admin: Zero address");
        require(msg.sender == adminAddress, "admin: wut?");
        adminAddress = _adminAddress;
        emit AdminUpdated(_adminAddress);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        ERC20VotesUpgradeable._afterTokenTransfer(from, to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        
        if(from == address(0) || to == address(0)){
            super._beforeTokenTransfer(from, to, amount);
        }else{
            revert("Non transferable token");
        }
    }

    function _delegate(address delegator, address delegatee) internal virtual override {
        require(!checkHighestStaker(0, delegator),"Top staker cannot delegate");
        super._delegate(delegator,delegatee);
    }

    function _authorizeUpgrade(address) internal view override {
        require(owner() == msg.sender, "Only owner can upgrade implementation");
    }



}