// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Campaign.sol";

/// @title CampaignFactory
/// @notice Deploys a fresh Campaign contract for each fundraiser, denominated
///         in one of two supported tokens that the creator chooses at
///         creation time: BOT (this chain's native currency, always
///         address(0) — nothing to configure) or USDT (an ERC20 token whose
///         address is fixed when this factory is deployed). The factory
///         keeps a public registry of every campaign so the frontend can
///         list them, but it never holds funds and has no control over any
///         campaign once deployed — the creator is the sole owner.
contract CampaignFactory {
    enum PaymentToken {
        BOT,
        USDT
    }

    /// @dev BOT is this chain's native currency, so it has no ERC20 contract —
    ///      address(0) is the sentinel Campaign uses to mean "native".
    address public constant botToken = address(0);
    address public immutable usdtToken;

    address[] public allCampaigns;
    mapping(address => address[]) public campaignsByCreator;

    event CampaignCreated(
        address indexed campaignAddress,
        address indexed creator,
        string title,
        uint256 goal,
        uint256 deadline,
        address token
    );

    constructor(address _usdtToken) {
        require(_usdtToken != address(0), "Invalid USDT token address");
        usdtToken = _usdtToken;
    }

    /// @notice Create a new campaign. Caller becomes its owner.
    /// @param _title Short campaign name.
    /// @param _description Longer pitch / story.
    /// @param _goal Funding goal, in the chosen token's smallest unit.
    /// @param _durationInDays How many days the campaign stays open.
    /// @param _paymentToken Which token this campaign is funded in: 0 = BOT (native), 1 = USDT.
    function createCampaign(
        string memory _title,
        string memory _description,
        uint256 _goal,
        uint256 _durationInDays,
        PaymentToken _paymentToken
    ) external returns (address campaignAddress) {
        address tokenAddress = _paymentToken == PaymentToken.BOT ? botToken : usdtToken;

        Campaign newCampaign = new Campaign(
            msg.sender,
            _title,
            _description,
            _goal,
            _durationInDays,
            tokenAddress
        );
        campaignAddress = address(newCampaign);

        allCampaigns.push(campaignAddress);
        campaignsByCreator[msg.sender].push(campaignAddress);

        emit CampaignCreated(campaignAddress, msg.sender, _title, _goal, newCampaign.deadline(), tokenAddress);
    }

    function getAllCampaigns() external view returns (address[] memory) {
        return allCampaigns;
    }

    function getCampaignsByCreator(address creator) external view returns (address[] memory) {
        return campaignsByCreator[creator];
    }

    function getCampaignCount() external view returns (uint256) {
        return allCampaigns.length;
    }
}
