// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.9;

import {IERC721} from '../node_modules/@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {ERC721} from '../node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol';

struct MirroredNFT {
	address owner;
	address nft;
	uint256 tokenId;
}

error NonTransferableNFT();
error ProhibitedMintFunction();

contract SapNFT is ERC721 {
	uint256 tokenIdCounter = 0;

	/// @dev Stores the data of each NFT (mapped by NFT token ID)
	mapping(uint256 => MirroredNFT) tokenData;

	address public owner;

	modifier onlyOwner() {
		require(msg.sender == owner, 'Only owner is allowed.');
		_;
	}

	constructor() ERC721('SapNFT', 'sapNFT') {
		owner = msg.sender;
	}

	/// @dev Override to disable transfer.
	function _transferFrom() public {
		revert NonTransferableNFT();
	}

	/// @dev Override to disable transfer.
	function _transfer() internal {
		revert NonTransferableNFT();
	}

	/// @dev Each NFT's unique data.
	function tokenInfo(uint256 tokenId) public returns (MirroredNFT memory) {
		return tokenData[tokenId];
	}

	function setOwner(address _owner) public onlyOwner {
		owner = _owner;
	}

	/// @dev Mint a NFT that mirrors user's NFT
	/// @dev Delegatecall, so using msg.sender gives the borrower's address
	function mint(address userNFT, uint256 userTokenId) public onlyOwner {
        require(!_exists(userTokenId), 'Token ID already exists');
		_safeMint(msg.sender, tokenIdCounter);

		// NOTE: This check isn't necessary? because
		//       (1) we transfer the underlying NFT to our contract when we mint sapNFT
		//       (2) we assume sanity check for (1) is done in SapLend.sol before minting sapNFT
		// TODO: Make sure that we aren't minting a new NFT that mirrors
		//       an already-mirrored NFT

		// store the mirrored NFT data
		tokenData[tokenIdCounter] = MirroredNFT({
				owner: msg.sender,
				nft: userNFT,
				tokenId: userTokenId
		});

		tokenIdCounter++;
	}

	/// @dev Burn the mirror NFT, which happens
	function burn() public onlyOwner {

	}
	
	/// @dev Overrride _mint to prevent ERC721's inherited mint, since we wrote our own mint function
	function _mint(address to, uint256 tokenId) internal override {
		revert ProhibitedMintFunction();
	}

	/// @dev Overrride _burn to prevent ERC721's inherited burn, since we wrote our own burn function
	function _burn(uint256 tokenId) internal override {
		revert ProhibitedMintFunction();
	}
}