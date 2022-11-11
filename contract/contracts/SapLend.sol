// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

import {IERC721} from '../node_modules/@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {ERC721} from '../node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol';

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

// Enums are indexed
// e.g. enum Dir {UP, LEFT, DOWN, RIGHT} corresponds to uint8 values 0, 1, 2 and 3.
enum Duration {
	days14, // 2 weeks
	days30, // 30 days
	days60, // 60 days
	days90, // 90 days
	days180 // 180 days
}

struct LoanTerm {
    uint256 rate; // interest rate, annualized (APY)
	uint256 start; // start date of loan
    Duration duration; // total duration of loan (in seconds)
    uint256 cvalue; // collateral value (value of NFT at the time of the loan bid creation)
    // uint256 cratio; // collateral ratio
    address lender; //lender's address
    uint256 loanId; // associated loan ID
    uint256 maxBorrowAmount; // max value amount
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

	/// @dev List of active loan IDs
	uint256[] public activeLoanIds;

	/// @dev Mapping of loan ID to active loan term
	mapping(uint256 => LoanTerm) public activeLoans;

	/// @dev Loan term that borrower will auto-accept (executed by the contract)

	address immutable public oracleAddress; // consider making mutable so that only owner (deployer of contract) can change it

	// borrower address => auto-accept loan term
	mapping(uint256 => AutoAcceptLoanTerm) public autoAcceptLoanTerms;

	/// @dev List of active loan bids
	uint256[] public activeLoanBidIds;

	/// @dev Mapping of loan ID to available bids (proposed by lenders)
	mapping(uint256 => mapping(uint256 => LoanTerm)) public activeLoanBids;

	// active list of users who want to borrow
	address[] public borrowWannabes;

	event LoanCreated(uint256 indexed loanId, address nft, uint256 tokenId, uint256 interest, uint256 startTime, uint256 borrowed);

	constructor(address _sapNFT, address _oracleAddress) {
		sapNFT = _sapNFT;
		oracleAddress = _oracleAddress; 
	}
	
	// puts an ID to a loan term
	function getLoanId(
		address nft,
		uint256 tokenId,
		address borrower,
		Duration minDuration,
		uint256 start
	) public pure returns (uint256 id) {
			return uint256(keccak256(abi.encode(nft, tokenId, borrower, minDuration, start)));
	}
	
	// puts an ID to a loan bid
	function getLoanBidId(
		address nft,
		uint256 tokenId,
		address lender,
		Duration duration,
		uint256 maxBorrowAmount,
		uint256 initatedTime
	) public pure returns (uint256 id) {
		return uint256(keccak256(abi.encode(nft, tokenId, lender, duration, maxBorrowAmount, initatedTime)));
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
		require(uint(minDuration) <= uint(minDuration), 'Min duration <= Max Duration');
		
		// 1) Register borrower's intent to borrow
        address borrower = msg.sender;
		borrowWannabes.push(borrower);

		// 2) Transfer borrower's NFT to our contract
        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);

		// 3) Mint SapNFT as a receipt of original (underlying) NFT deposit
		(bool success, bytes memory data) = address(sapNFT).delegatecall(
				abi.encodeWithSignature("mint(address userNFT, uint256 userTokenId)", nft, tokenId)
		);
		require(success, 'Minting of NFT failed!');

		// 4) Save the auto-accept loan term data in our contract
		AutoAcceptLoanTerm memory aaLoanTerm = AutoAcceptLoanTerm({
			rate : rate,
			valuation : valuation,
			cratio : cratio,
			nft : nft,
			tokenId : tokenId,
			borrower: msg.sender,
			minDuration : minDuration,
			maxDuration : maxDuration
		});
	
		uint256 loanId = getLoanId(nft, tokenId, borrower, minDuration, block.timestamp);
		autoAcceptLoanTerms[loanId] = aaLoanTerm;
	}

	/// @dev Lender comes in and makes a bid to give the borrower x amount of money
	/// Returns an array with index 0 being the interest rate (whole numbers only) and index 1 being the bidded borrowing value 
	function proposeLoanTerm( // ie., bidLoanTermForBorrower
		uint256 rate,
		Duration duration,
		uint256 value,
		uint256 loanId, /// @dev TODO don't know if this should be here
		uint256 maxBorrowAmount
	) public {
		require(rate <= rateCap(), 'Exceeds rate cap!');

		LoanTerm memory loanTerm = LoanTerm({
			 rate: rate,
			 start: 0, // start is when loan is accepted by borrower
			 duration: duration,
			 cvalue: value, // value of NFT
			 lender: msg.sender,
			 loanId: loanId,
			 maxBorrowAmount: maxBorrowAmount
		});

		AutoAcceptLoanTerm memory aaLoanTerm = autoAcceptLoanTerms[loanId];

		uint256 loanBidId = getLoanBidId(
			aaLoanTerm.nft,
			aaLoanTerm.tokenId,
			msg.sender,
			duration,
			maxBorrowAmount,
			block.timestamp
		);

		activeLoanBids[loanId][loanBidId] = loanTerm;
	}

	/// @dev Borrower accepts any loan term associated to their intent to borrow
	function acceptBorrow(
		uint256 loanBidId
	) public {
		/*
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
		*/

		uint256 loanId = activeLoans[loanBidId].loanId;
		require(loanId == 0, 'Loan already exists for the ID.');

		AutoAcceptLoanTerm memory aaLoanTerm = autoAcceptLoanTerms[loanId];
		require(msg.sender == aaLoanTerm.borrower, 'Sender is not the initiated borrower.');

		LoanTerm memory loanTerm = activeLoanBids[loanId][loanBidId];

		// TODO: actual borrowing part
		activeLoanIds.push(loanBidId);
	}

	// Kevin
	function closeLoan() public {
	}

	// Antony
	// Check if they have an intent to borrow active
	// Close out any active bids (closeBid())
	// Borrower pays
	function closeIntentToBorrow() public {
	}

	// Manas
	// Check if they have an active bid
	// close it and remove it from the active bid list
	// 
	function closeBid() public {
	}

	//
	function checkOracle() public {
	}

	function rateDecimals() public pure returns (uint256) {
		return 10 ** 2; // two decimals
	}

	function rateCap() public pure returns (uint256) {
		return 1000 * rateDecimals(); // max is 1000%
	}

		function _isERC721(address nftAddress) internal view returns (bool) {
        // return nftAddress.supportsInterface(type(IERC721).interfaceId);
				// TODO: fix this
				return false;
    }

	// Will check signature to make sure that the wallet in our server has signed off on this price, 
	// relatively centralized method . . . will look to iterate upon this in the future
	// We are essentially functioning as our own oracle at this point

	function validatePrice(uint216 price, uint256 deadline, uint8 v, bytes32 r, bytes32 s, address nftContract) public view { 
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
