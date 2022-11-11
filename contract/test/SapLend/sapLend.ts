const { expect } = require("chai");


describe("SapLend contract", function () {
  it("Deployment should assign the total supply of tokens to the owner", async function () {
    const [owner] = await ethers.getSigners();

    const SapLen = await ethers.getContractFactory("SapLend");

    const hardhatSapLend = await SapLend.deploy();

    const ownerBalance = await hardhatToken.balanceOf(owner.address);
    expect(await hardhatToken.totalSupply()).to.equal(ownerBalance);
  });
});