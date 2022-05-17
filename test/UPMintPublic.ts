import { ethers, network } from "hardhat"
import { expect } from "chai"
import { UP, UPController, UPMintPublic } from "../typechain-types"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

describe("UPMintPublic", () => {
  let upToken: UP
  let upController: UPController
  let upMintPublic: UPMintPublic
  let addr1: SignerWithAddress

  beforeEach(async () => {
    const [a1] = await ethers.getSigners()
    addr1 = a1
    upToken = await ethers
      .getContractFactory("UP")
      .then((factory) => factory.deploy())
      .then((instance) => instance.deployed())
    upController = await ethers
      .getContractFactory("UPController")
      .then((factory) => factory.deploy(upToken.address))
      .then((instance) => instance.deployed())
    upMintPublic = await ethers
      .getContractFactory("UPMintPublic")
      .then((factory) => factory.deploy(upToken.address, upController.address, 100))
      .then((instance) => instance.deployed())
  })

  it('Should set a new "mintRate"', async () => {
    const signerUpController = upMintPublic.connect(addr1)
    await upMintPublic.setMintRate(100)
    expect(await upMintPublic.mintRate()).equal(100)
  })

  it('Shouldnt set a new "mintRate" because not enough permissions', async () => {
    const [, addr2] = await ethers.getSigners()
    const addr2UpController = upMintPublic.connect(addr2)
    await expect(addr2UpController.setMintRate(100)).revertedWith(
      "Ownable: caller is not the owner"
    )
  })

  it("Should mint UP at premium rates #1", async () => {
    await addr1.sendTransaction({
      to: upMintPublic.address,
      value: ethers.utils.parseEther("5")
    })
    await upToken.mint(upMintPublic.address, ethers.utils.parseEther("2"))
    await upMintPublic.mintUP({ value: ethers.utils.parseEther("100") })
    expect(await upToken.balanceOf(addr1.address)).equal(ethers.utils.parseEther("237.5"))
  })

  it("Should mint UP at premium rates #2", async () => {
    await addr1.sendTransaction({
      to: upMintPublic.address,
      value: ethers.utils.parseEther("5")
    })
    await upToken.mint(upMintPublic.address, ethers.utils.parseEther("2"))
    await upMintPublic.mintUP({ value: ethers.utils.parseEther("31") })
    expect(await upToken.balanceOf(addr1.address)).equal(ethers.utils.parseEther("73.625"))
  })

  it("Should mint UP at premium rates #3", async () => {
    await addr1.sendTransaction({
      to: upMintPublic.address,
      value: ethers.utils.parseEther("5")
    })
    await upToken.mint(upMintPublic.address, ethers.utils.parseEther("2"))
    await upMintPublic.mintUP({ value: ethers.utils.parseEther("1233") })
    expect(await upToken.balanceOf(addr1.address)).equal(ethers.utils.parseEther("2928.375"))
  })

  it("Should mint UP at premium rates #4", async () => {
    await addr1.sendTransaction({
      to: upMintPublic.address,
      value: ethers.utils.parseEther("5")
    })
    await upToken.mint(upMintPublic.address, ethers.utils.parseEther("2"))
    await upMintPublic.mintUP({ value: ethers.utils.parseEther("999.1") })
    expect(await upToken.balanceOf(addr1.address)).equal(ethers.utils.parseEther("2372.8625"))
  })

  it("Should mint UP at premium rates #5", async () => {
    await network.provider.send("hardhat_setBalance", [
      addr1.address,
      ethers.utils.parseEther("99900").toHexString()
    ])
    await addr1.sendTransaction({
      to: upMintPublic.address,
      value: ethers.utils.parseEther("5")
    })
    await upToken.mint(upMintPublic.address, ethers.utils.parseEther("2"))
    await upMintPublic.mintUP({ value: ethers.utils.parseEther("91132.42") })
    expect(await upToken.balanceOf(addr1.address)).equal(ethers.utils.parseEther("216439.4975"))
  })

  it("Should fail minting UP because payable value is zero", async () => {
    await expect(upMintPublic.mintUP({ value: 0 })).revertedWith("INVALID_PAYABLE_AMOUNT")
  })

  it("Should mint zero UP because virtual price is zero", async () => {
    await upMintPublic.mintUP({ value: ethers.utils.parseEther("100") })
    expect(await upToken.balanceOf(addr1.address)).equal(0)
  })

  it("Shouldn't mint up because contract is paused", async () => {
    await upMintPublic.pause()
    await expect(upMintPublic.mintUP({ value: ethers.utils.parseEther("100") })).revertedWith(
      "Pausable: pause"
    )
  })
})
