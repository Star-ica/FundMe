# Commons — a non-custodial GoFundMe clone (BOT / USDT)

Each fundraiser deploys their **own** `Campaign` contract through a shared
`CampaignFactory`. The factory only deploys and keeps a registry — it never
holds funds and has no admin power over any campaign. `Campaign.owner` is
set to the wallet that called `createCampaign`, so the creator is the sole
address that can withdraw.

Campaigns are funded in an ERC20 token, not raw ETH. The creator picks
**BOT** or **USDT** when they create the campaign; the factory is deployed
once with both token addresses fixed, so every campaign it spawns can only
be denominated in one of those two.

## Files

- `contracts/IERC20.sol` — minimal ERC20 interface used by the other two contracts.
- `contracts/Campaign.sol` — one fundraiser's contract (donate, withdraw, refund) in its chosen token.
- `contracts/CampaignFactory.sol` — deploys `Campaign` instances, holds the BOT/USDT addresses, lists campaigns.
- `frontend/index.html` — wallet-connected dashboard UI: create a campaign, browse, donate, withdraw.

## 1. Get the BOT and USDT token addresses for your network

- **USDT** — use the official USDT contract address for whichever network you're deploying to (its address differs by chain: Ethereum mainnet, a testnet, BSC, Polygon, etc. — look it up for your target network, don't reuse an address from a different chain).
- **BOT** — the address of your own BOT token's ERC20 contract. If you haven't deployed BOT yet, deploy that first and copy its address.
- On a testnet, you'll likely want mock/test versions of both tokens (a test USDT and a test BOT) so you can mint yourself a balance to test with.

## 2. Deploy the contracts

Easiest path is [Remix](https://remix.ethereum.org):

1. Create `contracts/IERC20.sol`, `contracts/Campaign.sol`, and `contracts/CampaignFactory.sol` in Remix with the contents from this project (same folder, so the relative imports resolve).
2. Compiler tab → select `0.8.19` (or any `^0.8.19` compatible version) → Compile.
3. Deploy & Run tab → environment "Injected Provider - MetaMask" → pick your target network → select `CampaignFactory`.
4. In the constructor fields, enter **`_botToken`** and **`_usdtToken`** — the two addresses from step 1 — then Deploy.
5. Copy the deployed factory's address.

Prefer Hardhat/Foundry? These files have no external imports beyond each
other, so `npx hardhat compile` or `forge build` will work with no extra
config — pass the same two constructor args when you deploy.

## 3. Point the frontend at your factory

Open `frontend/index.html` and update:

```js
const DEFAULT_FACTORY_ADDRESS = "0xYourNewFactoryAddress";
```

The page reads `botToken()` / `usdtToken()` off the factory itself and
fetches each token's symbol and decimals on load — you don't need to hardcode
the token addresses anywhere in the frontend.

Then just open the file in a browser, or serve it:

```bash
cd frontend
python3 -m http.server 8000
# visit http://localhost:8000
```

## How funding works now (ERC20, not ETH)

Donating to a campaign is two transactions instead of one:

1. **Approve** — the donor grants the campaign contract permission to pull up to the donation amount from their token balance (`token.approve(campaignAddress, amount)`).
2. **Donate** — the campaign then calls `transferFrom` to pull that amount in (`campaign.donate(amount)`).

The frontend handles this automatically: it checks the donor's current
allowance first, only sends an approve transaction if it's insufficient,
then sends the donate transaction. Donors will see one or two wallet prompts
depending on whether they've already approved enough.

Creators pick the token per campaign via a `PaymentToken` enum on
`createCampaign`: `0 = BOT`, `1 = USDT`. All amounts (goal, donations) are
stored in that token's smallest unit, so decimals matter — USDT is commonly
6 decimals, most other tokens (BOT included, unless you built it otherwise)
are 18. The frontend reads each token's `decimals()` on-chain rather than
assuming, so this works either way.

## Notes & things to decide before going to mainnet

- **Withdrawal model**: currently the owner can withdraw the running balance at any time (no goal threshold). If you want an "all-or-nothing" Kickstarter-style model instead, uncomment the goal check in `Campaign.withdraw()`.
- **Refunds**: donors can call `refund()` once the deadline passes if the goal wasn't met. Remove this if you want funds to always go to the creator regardless of outcome.
- **Fees**: there are none built in. If you want a platform fee, take a small cut inside `withdraw()` before sending the rest to `owner`.
- **Token trust**: this contract trusts whatever ERC20 you pass in at factory-deploy time to behave like a standard token (no fee-on-transfer, no rebasing). If BOT has non-standard transfer behavior, test `donate()`/`withdraw()`/`refund()` against it specifically before launch.
- **Audit**: this is a straightforward, unaudited reference implementation. Get a professional review before handling real funds at any scale.
- **Gas**: every new campaign is a full contract deployment, which costs more gas than a single shared contract with per-campaign structs. That's the trade-off for "each creator truly owns their own contract."
