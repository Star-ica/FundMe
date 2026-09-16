// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

/// @title Campaign
/// @notice A single fundraising campaign, funded in one token chosen by its
///         creator at creation time: either BOT (this chain's native
///         currency, represented as `token == address(0)`) or USDT (an
///         ERC20 token). Deployed by CampaignFactory, but `owner` is set to
///         the creator's address, so the creator has full control of this
///         contract — they can withdraw funds, and only they can. The
///         factory has no admin rights over deployed campaigns.
contract Campaign {
    address public owner;
    address public factory;
    address public token; // address(0) = native BOT, otherwise an ERC20 (e.g. USDT)

    string public title;
    string public description;
    uint256 public goal;       // in the token's smallest unit (18 decimals for native BOT)
    uint256 public deadline;   // unix timestamp
    uint256 public totalRaised;
    bool public claimed;

    struct Donation {
        address donor;
        uint256 amount;
        uint256 timestamp;
    }

    Donation[] public donations;
    mapping(address => uint256) public contributions;

    event DonationReceived(address indexed donor, uint256 amount, uint256 newTotal);
    event Withdrawn(address indexed owner, uint256 amount);
    event Refunded(address indexed donor, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not campaign owner");
        _;
    }

    constructor(
        address _owner,
        string memory _title,
        string memory _description,
        uint256 _goal,
        uint256 _durationInDays,
        address _token
    ) {
        require(_owner != address(0), "Invalid owner");
        require(_goal > 0, "Goal must be > 0");
        require(_durationInDays > 0, "Duration must be > 0");

        owner = _owner;
        factory = msg.sender;
        title = _title;
        description = _description;
        goal = _goal;
        deadline = block.timestamp + (_durationInDays * 1 days);
        token = _token; // address(0) is valid here — it means native BOT
    }

    function isNative() public view returns (bool) {
        return token == address(0);
    }

    /// @notice Donate to this campaign.
    ///         - Native (BOT): send value with the call; `amount` is ignored,
    ///           `msg.value` is what's recorded.
    ///         - ERC20 (USDT): pass `amount`, send no value, and have
    ///           approved this contract for at least `amount` beforehand.
    function donate(uint256 amount) external payable {
        require(block.timestamp < deadline, "Campaign has ended");

        uint256 recorded;
        if (isNative()) {
            require(msg.value > 0, "Donation must be > 0");
            recorded = msg.value;
        } else {
            require(msg.value == 0, "Do not send native currency to a token campaign");
            require(amount > 0, "Donation must be > 0");
            recorded = amount;
            bool ok = IERC20(token).transferFrom(msg.sender, address(this), amount);
            require(ok, "Token transfer failed");
        }

        contributions[msg.sender] += recorded;
        totalRaised += recorded;
        donations.push(Donation(msg.sender, recorded, block.timestamp));

        emit DonationReceived(msg.sender, recorded, totalRaised);
    }

    /// @notice Owner withdraws whatever balance the contract holds.
    /// @dev No goal-reached requirement by default — uncomment the check
    ///      below to enforce an all-or-nothing model instead.
    function withdraw() external onlyOwner {
        uint256 amount;
        claimed = true;

        if (isNative()) {
            amount = address(this).balance;
            require(amount > 0, "No funds to withdraw");
            // require(totalRaised >= goal, "Goal not reached"); // uncomment for all-or-nothing
            (bool sent, ) = payable(owner).call{value: amount}("");
            require(sent, "Withdraw failed");
        } else {
            amount = IERC20(token).balanceOf(address(this));
            require(amount > 0, "No funds to withdraw");
            // require(totalRaised >= goal, "Goal not reached"); // uncomment for all-or-nothing
            bool ok = IERC20(token).transfer(owner, amount);
            require(ok, "Withdraw failed");
        }

        emit Withdrawn(owner, amount);
    }

    /// @notice Donors can reclaim their contribution if the deadline passed
    ///         and the goal was never reached.
    function refund() external {
        require(block.timestamp >= deadline, "Campaign still active");
        require(totalRaised < goal, "Goal was met, no refunds");

        uint256 amount = contributions[msg.sender];
        require(amount > 0, "No contribution found");

        contributions[msg.sender] = 0;
        totalRaised -= amount;

        if (isNative()) {
            (bool sent, ) = payable(msg.sender).call{value: amount}("");
            require(sent, "Refund failed");
        } else {
            bool ok = IERC20(token).transfer(msg.sender, amount);
            require(ok, "Refund failed");
        }

        emit Refunded(msg.sender, amount);
    }

    function getDonationsCount() external view returns (uint256) {
        return donations.length;
    }

    function getDonation(uint256 index) external view returns (address, uint256, uint256) {
        Donation memory d = donations[index];
        return (d.donor, d.amount, d.timestamp);
    }

    function getDetails()
        external
        view
        returns (
            address _owner,
            address _token,
            string memory _title,
            string memory _description,
            uint256 _goal,
            uint256 _deadline,
            uint256 _totalRaised,
            uint256 _balance,
            bool _claimed
        )
    {
        uint256 balance = isNative() ? address(this).balance : IERC20(token).balanceOf(address(this));
        return (owner, token, title, description, goal, deadline, totalRaised, balance, claimed);
    }

    /// @notice Lets a native-BOT campaign receive plain transfers as donations.
    ///         Reverts for token campaigns — send USDT via donate(amount) instead.
    receive() external payable {
        require(isNative(), "This campaign only accepts USDT via donate()");
        require(block.timestamp < deadline, "Campaign has ended");
        require(msg.value > 0, "Donation must be > 0");

        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;
        donations.push(Donation(msg.sender, msg.value, block.timestamp));

        emit DonationReceived(msg.sender, msg.value, totalRaised);
    }
}
