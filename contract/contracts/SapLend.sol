// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import {SapNFT} from './SapNFT.sol';

// What's in a loan term?

// - Interest rate (APY)
// - Loan start date
// - Loan duration
// - Loan amount
// - NFT valuation
// - Collateral % (Max LTV)
// - Borrower account
// - Lender account (in future version, will be multiple lenders)

// - Meet up date? Reevaluate NFT value between Lender and Borrower?
// >> brainstorm -- intentional/accidental no-shows
// >> lenders are incentivized to show up

enum Duration {
	14, 
	30,
	60,
	90, 
	180
}

struct LoanTerm {
    uint256 rate; // interest rate, annualized (APY)
	uint256 start; // start date of loan
    Duration duration; // total duration of loan (in seconds)
    uint256 amount; // notional amount of loan
    uint256 cratio; // collateral Ratio
    address lender; //lender's address
    address borrower; //borrower's address
		address nft; // address of NFT used for loan
		uint256 tokenId; // token ID of the NFT used for loan

    uint256 valuation;
		uint256 meetUpInterval;
}

// Ask Allan: how do we agree on duration of the loan?
// Ask Allan: liquidation engine?
// Ask Allan (maybe): Should we transfer NFT to our contract when user intens to borrow?

struct AutoAcceptLoanTerm {
	uint256 rate;
	uint256 valuation;
	uint256 cratio; // 0 - 100% ==> two decimal places (0 - 100) * 100
	address borrower;
	address nft;
	uint256 tokenId;
	Duration minDuration;
	Duration maxDuration;
}

contract SapLend {
	address immutable public sapNFT; // address where SapNFT.sol is deployed

	address immutable public oracleAddress; // consider making mutable so that only owner (deployer of contract) can change it

	// borrower address => auto-accept loan term
	mapping(address => AutoAcceptLoanTerm) private autoAcceptLoanTerms;

	// active list of users who want to borrow
	address[] public borrowWannabes;

	constructor(address _sapNFT, address _oracleAddress) {
		sapNFT = _sapNFT;
		oracleAddress = _oracleAddress; 
	}
	
	/// @dev Borrower initiates the loan term
	function initiateIntentToBorrow(
		uint256 rate,
		uint256 valuation,
		uint256 cratio,
		address nft,
		uint256 tokenId,
		Duration minDuration,
		Duration maxDuration
	) public {
		require(nft != address(0), 'NFT address must be non-zero');
		require(_isERC721(nft), 'NFT address is not ERC721');
		require(IERC721(nft).ownerOf(tokenId) == msg.sender, 'Borrower must own the NFT');
		// 10,000 b/c 100% in solidity is 10,000, 69.42 would be 6942
		require(cratio <= 10000, 'C-Ratio must be 100% or less');
		// Require that minDuration index is smaller or equal to maxDuration index
		require(minDuration.ordinal() <= maxDuration.ordinal(), 'Min duration <= Max Duration');
		
		// 1) Register borrower's intent to borrow
        address borrower = msg.sender;
		borrowWannabes.push(borrower)

		// 2) Transfer borrower's NFT to our contract
        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);

		// 3) Mint SapNFT as a receipt of original (underlying) NFT deposit
		(bool success, bytes memory data) = SapNFT(sapNFT).delegatecall(
				abi.encodeWithSignature("mint(address userNFT, uint256 userTokenId)", nft, tokenId)
		);
		require(success, 'Minting of NFT failed!');

		// 4) Save the auto-accept loan term data in our contract
		AutoAcceptLoanTerm aaLoanTerm = AutoAcceptLoanTerm({
			rate: rate,
			valuation: valuation,
			cratio: cratio,
			borrower: msg.sender,
			duration: duration
		});
		
		autoAccepts[msg.sender] = loanTerm;
	}
    

		function _isERC721(address nftAddress) internal view returns (bool) {
        return nftAddress.supportsInterface(type(IERC721).interfaceId);
    }

	// Will check signature to make sure that the wallet in our server has signed off on this price, 
	// relatively centralized method . . . will look to iterate upon this in the future
	// We are essentially functioning as our own oracle at this point

	function validatePrice(uint216 price, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public view { 
        require(block.timestamp < deadline, "deadline over");
        require(
            ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19Ethereum Signed Message:\n111",
                        price,
                        deadline,
                        block.chainid,
                        address(nftContract)
                    )
                ),
                v,
                r,
                s
            ) == oracleAddress,
            "not signed by Illini Blockchain oracle!"
        );
        // require(price < maxPrice, "max price"); 
		// the Max Price seems like a safety switch to stop all new liquidations . . .
    }

}
