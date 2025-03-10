# Smart Contract Documentation: PawsForHope token and Related Contracts

## Overview
This project implements a decentralized platform for pet-related use cases, leveraging blockchain technology. The system incorporates a token (USDCPaws), donation management, a pet search mechanism, and user registration.

---

## Key Components and Functionality

### 1. **USDCPaws Token Contract**
- **Purpose:** Provides a fungible token used within the platform.
- **Core Functions:**
  - `mint(address to, uint256 amount)`: Mints new tokens for a specified address.
  - `transfer(address to, uint256 amount)`: Transfers tokens between users.
- **Use Case:** Serves as the primary token for transactions, including rewards and donations.

---

### 2. **Donation Management Contract (`Donate`)**
- **Purpose:** Manages donation posts for pet-related causes.
- **Core Functions:**
  - `createDonationPost(uint256 targetAmount, string description)`: Allows registered entities to create donation campaigns.
  - `donateToPost(uint256 postId, uint256 amount)`: Allows users to donate USDC tokens to campaigns.
  - `closePost(uint256 postId)`: Closes donation campaigns and allocates the collected funds.
- **Reward Mechanism:** Donors receive "PawsForHope" tokens as a reward for contributions.

---

### 3. **Pet Search Contract (`FindPet`)**
- **Purpose:** Enables users to create and manage posts for finding lost pets.
- **Core Functions:**
  - `createPost(uint256 amount)`: Posts a reward for finding a lost pet.
  - `closePost(uint256 postId, address beneficiary)`: Closes the search and rewards the finder.
- **Reward Mechanism:** The finder is rewarded with USDC tokens and additional PawsForHope tokens.

---

### 4. **Redemption Contract (`Redeem`)**
- **Purpose:** Allows users to redeem tokens for goods or services.
- **Core Functions:**
  - `createPost(uint256 stock, uint256 price)`: Creates redeemable offers.
  - `redeemItem(uint256 postId)`: Facilitates token redemption for items.
- **Stock Management:** Tracks item availability and deducts redeemed items.

---

### 5. **User Registration Contract (`RegisterUsers`)**
- **Purpose:** Handles the registration of users and entities.
- **Core Functions:**
  - `registerUser(address user)`: Registers individual users.
  - `registerEntity(address entity)`: Registers organizations or entities.
- **Agent Management:** Restricts certain functions to authorized agents.

---

### 6. **PawsForHopeToken Contract**
- **Purpose:** Implements an ERC20 token with additional features for the platform.
- **Core Functions:**
  - **Token Minting and Burning:** Agents can mint or burn tokens.
  - **Account Freezing:** Freeze specific accounts or globally restrict transfers.
  - **Forced Transfers:** Agents can reallocate tokens if necessary.
- **Use Case:** Rewards and utility token across the platform.

---

## Entity Relationship Diagram

Below is the **Entity Relationship Diagram** that illustrates the relationships between the contracts: ONE TO MANY   one on one 

```plaintext
+-------------------+      +---------------------+
|   RegisterUsers   |<---->|      Donate         |
+-------------------+      +---------------------+
           ^                       ^
           |                       |
           v                       v
+-------------------+      +---------------------+
|     USDCPaws       |<---->|     FindPet         |
+-------------------+      +---------------------+
           ^                       ^
           |                       |
           v                       v
+-------------------+      +---------------------+
|  PawsForHopeToken |      |      Redeem         |
+-------------------+      +---------------------+



# Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/deploy.js || npx hardhat run ./ignition/modules/deploy.js --network lisk-sepolia
npx hardhat verify --network lisk-sepolia <deployed address>

```
93jRVeROldwCrly2OEMfnW1qS5E5JWnez3SIhkmFMroEr3kPziDDVjTbQFetdcycfv_7c6BU0NpD7noMbhykYA

97d00261c79e0942750e28da282db75c

<!-- 
yarn deploy
yarn run v1.23.0-20200615.1913
$ npx hardhat deploy --tags all --network sepolia
Nothing to compile
No need to generate any newer typings.
Deploying RegisterUsers...

RegisterUsers deployed to: 0xE104860e2caE646f2F2C96F4164a8459061cc988
Deploying PawsForHopeToken...
reusing "PawsForHopeToken" at 0x5091F028b9a4151EE9acDF255B3a55263508dEa3
PawsForHopeToken deployed to: 0x5091F028b9a4151EE9acDF255B3a55263508dEa3
Deploying USDCPaws...

USDCPaws deployed to: 0x17896b08cabD2759cc2047a8e726845CbEE9a3fB
Deploying Donate...
deploying "Donate" (tx: 0xb402a261f48bd10e0f4e4be0b775daa41c47cfb8748cba04b836b9d862ed04f4)...: deployed at 0x3130f25D5c596fAd684381f5AafD47A9446a73D5 with 1881240 gas

Deploying FindPet...

FindPet deployed to: 0xd4475C6409a6F7a3AC042aaBE53f8F455081610f
Deploying Redeem...
deploying "Redeem" (tx: 0xb1556923845fb9489f6c68902dcc3e5fac8068a2901ae08be0d88b42065be0b0)...: deployed at 0x77df767288b7C632D7E6F9dF1EC83117f4B8F942 with 1142097 gas


Deployment completed successfully!
Done in 48.70s.


reusing "RegisterUsers" at 0xE104860e2caE646f2F2C96F4164a8459061cc988
reusing "PawsForHopeToken" at 0x5091F028b9a4151EE9acDF255B3a55263508dEa3
reusing "USDCPaws" at 0x17896b08cabD2759cc2047a8e726845CbEE9a3fB
Donate deployed to: 0x244747e42Aa15452D08Ef3d58B9693f6f49911c7
reusing "FindPet" at 0x61C78Ace8E15C47F81D9CCd1eDDe734b2C4f0D9E 0xeB6deFC2b3588e8C807701DA8b31Bd52E39f0039  //  0xd4475C6409a6F7a3AC042aaBE53f8F455081610f
Redeem deployed to: 0x77df767288b7C632D7E6F9dF1EC83117f4B8F942


 -->


<!-- 
Deploying RegisterUsers...
reusing "RegisterUsers" at 0xE104860e2caE646f2F2C96F4164a8459061cc988
RegisterUsers deployed to: 0xE104860e2caE646f2F2C96F4164a8459061cc988
Deploying PawsForHopeToken...
deploying "PawsForHopeToken" (tx: 0x86d39d5f62330498caa321b34daedaa59f1822f6aa69b507503c094511a9c29c)...: deployed at 0x5091F028b9a4151EE9acDF255B3a55263508dEa3 with 1275947 gas
PawsForHopeToken deployed to: 0x5091F028b9a4151EE9acDF255B3a55263508dEa3
Deploying USDCPaws...
deploying "USDCPaws" (tx: 0x8ee705950104fa55488828fafe5f7bd52fdcbed31041632222c1228bb5d2f226)...: deployed at 0x17896b08cabD2759cc2047a8e726845CbEE9a3fB with 693552 gas
USDCPaws deployed to: 0x17896b08cabD2759cc2047a8e726845CbEE9a3fB
Deploying Donate...
deploying "Donate" (tx: 0x170de6891e0789991217697bd94dca654ef2110f0d15e49959771b01c21dab11)...: deployed at 0x59a89b06D3C692Ef5a516093C42F1ab845556Cee with 1797252 gas
Donate deployed to: 0x59a89b06D3C692Ef5a516093C42F1ab845556Cee
Deploying FindPet...
deploying "FindPet" (tx: 0x47594a2a236829a6211b4d3c87ccb6d571b244ae61e8a3b49f3bf54ba53b7b9b)...: deployed at 0xd4475C6409a6F7a3AC042aaBE53f8F455081610f with 1644404 gas
FindPet deployed to: 0xd4475C6409a6F7a3AC042aaBE53f8F455081610f
Deploying Redeem...
deploying "Redeem" (tx: 0xc00d3eb0997f3a9ec516fa14a9aaa7e2f850c67239b1952ee60128a9007d335f)...: deployed at 0x76e0a9DA47fe2D86bDfe72980B927547C52064Ba with 1090713 gas
Redeem deployed to: 0x76e0a9DA47fe2D86bDfe72980B927547C52064Ba

Deployment completed successfully!
Done in 68.48s. -->


<!-- contract 
RegisterUsers deployed to: 0xE104860e2caE646f2F2C96F4164a8459061cc988
PawsForHopeToken deployed to: 0x5091F028b9a4151EE9acDF255B3a55263508dEa3
USDCPaws deployed to: 0x17896b08cabD2759cc2047a8e726845CbEE9a3fB
Donate deployed to: 0x59a89b06D3C692Ef5a516093C42F1ab845556Cee
FindPet deployed to: 0xd4475C6409a6F7a3AC042aaBE53f8F455081610f
Redeem deployed to: 0x76e0a9DA47fe2D86bDfe72980B927547C52064Ba
 -->




<!-- Deploying RegisterUsers...
reusing "RegisterUsers" at 0xA1bC15400b27de56fd49B2602E8CDE718528980F
RegisterUsers deployed to: 0xA1bC15400b27de56fd49B2602E8CDE718528980F
Deploying PawsForHopeToken...
reusing "PawsForHopeToken" at 0x867FB814457854b8Fcc8C6A0f218CbeCda67A914
PawsForHopeToken deployed to: 0x867FB814457854b8Fcc8C6A0f218CbeCda67A914
Deploying Donate...
reusing "Donate" at 0x51AeEa0B00ca68e6755e1D0DEfaA6932a1972fBa
Donate deployed to: 0x51AeEa0B00ca68e6755e1D0DEfaA6932a1972fBa
Deploying FindPet...
reusing "FindPet" at 0x28E3F40b08dDF9dbDb3d5EF71E1F8783ffa2B18A
FindPet deployed to: 0x28E3F40b08dDF9dbDb3d5EF71E1F8783ffa2B18A
Deploying Redeem...
reusing "Redeem" at 0x996A037aE0CB6Dfdfc76eA6D431f1d9327477752
Redeem deployed to: 0x996A037aE0CB6Dfdfc76eA6D431f1d9327477752
Deploying USDCPaws...
deploying "USDCPaws" (tx: 0xf7225c6834310925544e1397bbec9346418b96bd0511e65e8b73f5d07f8e169e)...: deployed at 0x942e416a411d4cEBba01B0a81A505ad35E5d0986 with 360218 gas
USDCPaws deployed to: 0x942e416a411d4cEBba01B0a81A505ad35E5d0986

Deployment completed successfully!
Done in 35.64s -->
