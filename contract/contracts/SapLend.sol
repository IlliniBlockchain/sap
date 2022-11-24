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

// TODO HAVE TO ADD TOKEN IDs to all of these  . . .

struct LoanTerm {
    uint256 rate; // interest rate, annualized (APY)
	uint256 start; // start date of loan
    Duration duration; // total duration of loan (in seconds)
    uint256 cvalue; // collateral value (value of NFT at the time of the loan bid creation)
    uint256 cratio; // collateral ratio
    address lender; //lender's address
    uint256 loanId; // associated loan ID
    uint256 BorrowedAmount; // max value amount
	address nft; // nft address
	uint256 tokenId;
}

struct BidTerm {
	uint256 rate; // interest rate, annualized (APY)
	uint256 proposedTime; // start date of loan
    Duration duration; // total duration of loan (in seconds)
    uint256 cvalue; // collateral value (value of NFT at the time of the loan bid creation)
    uint256 cratio; // collateral ratio
    address lender; //lender's address
    uint256 intentId; // associated loan ID
    uint256 maxBorrowAmount; // max value amount
	address nft; // nft address
	uint256 tokenId;
}

// Ask Allan: how do we agree on duration of the loan?
// Ask Allan: liquidation engine?
// Ask Allan (maybe): Should we transfer NFT to our contract when user intens to borrow?

struct AutoAcceptLoanTerm {
	uint256 rate;
	uint256 proposedTime;
	uint256 cvalue;
	uint256 cratio; // 0 - 100% ==> two decimal places (0 - 100) * 100
	uint256 requestedAmount;
	address borrower;
	Duration minDuration;
	Duration maxDuration;
	address nft;
	uint256 tokenId;
}

contract SapLend {

	/// @dev address where SapNFT.sol is deployed, set in constructor
	address immutable public sapNFT; 

	/// @dev address of our "inhouse" oracle, set in constructor
	address immutable public oracleAddress; 

	/// @dev List of active loan IDs
	uint256[] public activeLoanIds;

	/// @dev active list of users who want to borrow
	address[] public borrowWannabes;

	/// @dev Mapping of loan ID to active loan term
	mapping(uint256 => LoanTerm) public activeLoans;

	/// @dev Mapping of Bid Term ID to BidTerm
	mapping (uint256 => BidTerm) public bidTerms;

	/// @dev Loan term that borrower will auto-accept (executed by the contract)
	/// @dev Mapping of Burrow Intent Ids to AutoAcceptLoanTerms
	mapping (uint256 => AutoAcceptLoanTerm) public autoAcceptLoanTerms;

	/// @dev burrower address => Burrower Intent Id(s) - not supporting multiple intents yet
	mapping(address => uint256) public burrowIntentIds;

	/// @dev Mapping of bidder address to their BidTerm ID(s) - not supporting multiple bids yet
	mapping (address => uint256) userActiveBidId;

	/// @dev Mapping of address to mapping of intent ID to array of available bids Ids(proposed by lenders)
	//  not sure we even need the double mapping with the burrower address
	mapping(address => mapping(uint256 => uint256[])) public activeLoanBidIds;



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
	function getBidTermId(
		address nft,
		uint256 tokenId,
		address lender,
		Duration duration,
		uint256 maxBorrowAmount,
		uint256 proposedTime
	) public pure returns (uint256 id) {
		return uint256(keccak256(abi.encode(nft, tokenId, lender, duration, maxBorrowAmount, proposedTime)));
	}

	/// @dev Borrower initiates the loan term
	function initiateIntentToBorrow(
		uint256 rate,
		uint256 cvalue,
		uint256 cratio,
		uint256 requestedAmount,
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

		// Antony is adding this CHECK TO MAKE SURE WE NEED THIS
		// also check magnitude conversion
		uint256 healthFactor = (requestedAmount / cvalue) * 10000;
		require (healthFactor <= cratio, "Can't burrow that much based on inputs for cvalue and cratio!");
		
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
			proposedTime : block.timestamp,
			cvalue : cvalue,
			cratio : cratio,
			requestedAmount : requestedAmount,
			borrower: msg.sender,
			minDuration : minDuration,
			maxDuration : maxDuration,
			nft : nft,
			tokenId: tokenId
		});
	
		uint256 intentId = getLoanId(nft, tokenId, borrower, minDuration, block.timestamp);

		autoAcceptLoanTerms[intentId] = aaLoanTerm;
		burrowIntentIds[msg.sender] = intentId;

		
	}

	/// @dev Lender comes in and makes a bid to give the borrower x amount of money
	/// Returns an array with index 0 being the interest rate (whole numbers only) and index 1 being the bidded borrowing value 
	function makeBid( // ie., bidLoanTermForBorrower
		uint256 rate,
		Duration duration,
		uint256 cvalue,
		uint256 cratio,
		uint256 intentId, // forgot why we put this . . .
		uint256 maxBorrowAmount,
		address borrower,
		address nft,
		uint256 tokenId
	) public {
		require(rate <= rateCap(), 'Exceeds rate cap!');

		// check magnitude conversion
		uint256 healthFactor = (maxBorrowAmount / cvalue) * 10000;
		require (healthFactor <= cratio, "Can't lend that much based on inputs for cvalue and cratio!");

		require(userActiveBidId[msg.sender] == 0); // makes sure that the bidder (the lender) doesn't already have an open bid

		BidTerm memory bidterm = BidTerm({
			 rate: rate,
			 proposedTime: block.timestamp, // start is when loan is accepted by borrower
			 duration: duration,
			 cvalue: cvalue, // value of NFT
			 cratio: cratio,
			 lender: msg.sender,
			 intentId: intentId,
			 maxBorrowAmount: maxBorrowAmount,
			 nft: nft,
			 tokenId : tokenId
		});

		AutoAcceptLoanTerm memory aaLoanTerm = autoAcceptLoanTerms[intentId];

		uint256 BidTermId = getBidTermId(
			aaLoanTerm.nft,
			aaLoanTerm.tokenId,
			msg.sender,
			duration,
			maxBorrowAmount,
			block.timestamp
		);

		/// @dev TODO : in the case that the bid has ALL better terms, initiate the loan and don't do bidding


		// adding to mapping from bidTermId to bidterm structs
		bidTerms[BidTermId] = bidterm;

		// getting reference to the array where available bids are stored (storage keyword gets reference)
		uint256[] storage openBids = activeLoanBidIds[borrower][intentId];

		// adding bid term Id to available Bids
		openBids.push(BidTermId);

	}

	/// @dev Borrower accepts any loan term associated to their intent to borrow
	function takeBid(
		uint256 BidId
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

		// checking that the bid was not already taken . . . making sure it is still available for taking
		uint256 loanId = activeLoans[BidId].loanId;
		require(loanId == 0, 'Loan already exists for the ID.');


		// making sure that burrower can take this bid
		AutoAcceptLoanTerm memory aaLoanTerm = autoAcceptLoanTerms[loanId];
		require(msg.sender == aaLoanTerm.borrower, 'Sender is not the initiated borrower.'); 

		// BidTerm memory bidTerm = activeLoanBidIds[aaLoanTerm.burrower][BidId];

		// TODO: actual borrowing part

		// LoanTerm memory loanTerm = LoanTerm ({
		// 	rate : bidTerm.rate, // interest rate, annualized (APY)
		// 	start : block.timestamp, // start date of loan
		// 	duration : bidTerm.duration, // total duration of loan (in seconds)
		// 	cvalue : bidTerm.cvalue, // collateral value (value of NFT at the time of the loan bid creation)
		// 	lender : bidTerm.lender, //lender's address
		// 	loanID : bidTerm.IntentId, // associated loan ID
		// 	maxBorrowAmount : bidTerm.maxBorrowAmount, // max value amount
		// 	nft : bidTerm.nft
		// }); 

		// uint256 loanID = getLoanId(address nft,
		// uint256 tokenId,
		// address borrower,
		// Duration minDuration,
		// uint256 start);

		// activeLoanIds.push(loanBidId);
	}

	// Kevin
	function closeLoan() public {

	}

	// Antony
	// Check if they have an intent to borrow active
	// Close out any active bids (closeBid())
	// Borrower pays
	function closeIntentToBorrow() public {
		// Putting this comment to open up branch on GH, Jongwon leave comments here
		uint256 borrowIntentId = burrowIntentIds[msg.sender];
		require (borrowIntentId != 0, "User does not have an open intent to burrow!");
		
		AutoAcceptLoanTerm memory aaLoanTerm = autoAcceptLoanTerms[borrowIntentId];

		// this require might be redundant b/c I don't see how this ever could not be true
		require(aaLoanTerm.borrower == msg.sender, "The user can only close out their own intentToBurrows");

		// using storage to get reference
		uint256[] storage openBids = activeLoanBidIds[msg.sender][borrowIntentId];
		
		// clearing all bids on this intentToBurrow ... how should we notify the lenders who have bidded?
		while (openBids.length != 0) {
			delete bidTerms[openBids[openBids.length - 1]]; // deleting bidTerm struct from mapping from bidTermIds to bidTerms
			openBids.pop();
		}

		// deleting (reseting) aaloanterm struct and the intentId
		delete autoAcceptLoanTerms[borrowIntentId];
		delete burrowIntentIds[msg.sender];


		// has to be a better way to do this . . . O(n) rn.  Could do some mapping from address to array index
		for (uint256 i = 0; i < borrowWannabes.length; ++i) {
			if (msg.sender == borrowWannabes[i]) {
				delete borrowWannabes[i];
				break;
			}
		}

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
