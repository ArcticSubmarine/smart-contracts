import { expect } from 'chai';
import { randomBytes } from 'crypto';
import { BigNumber, Contract } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ZERO_ADDRESS } from '../lib/constants';
import DeepSquare from '../typings/DeepSquare';
import SpenderSecurity from '../typings/SpenderSecurity';
import IERC20Metadata from '../typings/openzeppelin/IERC20Metadata';
import { createERC20Agent, ERC20Agent } from './testing/ERC20Agent';
import setup from './testing/setup';

describe('DeepSquareBridge', () => {
  let owner: SignerWithAddress;
  let accounts: SignerWithAddress[];
  let DPS: DeepSquare;
  let SQA: IERC20Metadata;
  let Security: SpenderSecurity;
  let Eligibility: Contract;
  let DeepSquareBridge: Contract;

  let agentDPS: ERC20Agent;
  let agentSQA: ERC20Agent;

  const INITIAL_ROUND = ethers.utils.parseUnits('210000000', 18); // 210k DPS

  async function setupAccount(
    account: SignerWithAddress,
    config: Partial<{ balanceSQA: number; balanceDPS: number; approved: number; tier: number }>,
  ) {
    if (config.balanceSQA && config.balanceSQA > 0) {
      await agentSQA.transfer(account, config.balanceSQA);
    }

    if (config.balanceDPS && config.balanceDPS > 0) {
      await agentDPS.transfer(account, config.balanceDPS);
    }

    if (config.approved && config.approved > 0) {
      await SQA.connect(account).approve(DeepSquareBridge.address, agentSQA.unit(config.approved));
      await DPS.connect(account).approve(DeepSquareBridge.address, agentDPS.unit(config.approved));
    }

    if (config.tier && config.tier > 0) {
      await Eligibility.setResult(account.address, {
        tier: config.tier,
        validator: 'Jumio Corporation',
        transactionId: ethers.utils.keccak256(randomBytes(16)),
      });
    }
  }

  beforeEach(async () => {
    ({ owner, accounts, Security, DPS, agentDPS } = await setup());

    const SquareFactory = await ethers.getContractFactory('Square');
    SQA = (await SquareFactory.deploy(Security.address)) as unknown as IERC20Metadata;
    agentSQA = await createERC20Agent(SQA);

    const EligibilityFactory = await ethers.getContractFactory('Eligibility');
    Eligibility = await EligibilityFactory.deploy();

    const DeepSquareBridgeFactory = await ethers.getContractFactory('DeepSquareBridge');
    DeepSquareBridge = await DeepSquareBridgeFactory.deploy(DPS.address, SQA.address, Eligibility.address, 250);

    await Security.grantRole(ethers.utils.id('SPENDER'), DeepSquareBridge.address);

    await SQA.transfer(DeepSquareBridge.address, (await SQA.balanceOf(owner.address)).sub(2000));
    await DPS.transfer(DeepSquareBridge.address, (await DPS.balanceOf(owner.address)).sub(3000));
  });

  describe('constructor', () => {
    it('should revert if the DPS contract is the zero address', async () => {
      const SaleFactory = await ethers.getContractFactory('DeepSquareBridge');
      await expect(SaleFactory.deploy(ZERO_ADDRESS, SQA.address, Eligibility.address, 25000)).to.be.revertedWith(
        'DeepSquareBridge: token is zero',
      );
    });

    it('should revert if the stable coin contract is the zero address', async () => {
      const SaleFactory = await ethers.getContractFactory('DeepSquareBridge');
      await expect(SaleFactory.deploy(DPS.address, ZERO_ADDRESS, Eligibility.address, 25000)).to.be.revertedWith(
        'DeepSquareBridge: stablecoin is zero',
      );
    });

    it('should revert if the eligibility contract is the zero address', async () => {
      const SaleFactory = await ethers.getContractFactory('DeepSquareBridge');
      await expect(SaleFactory.deploy(DPS.address, SQA.address, ZERO_ADDRESS, 25000)).to.be.revertedWith(
        'DeepSquareBridge: eligibility is zero',
      );
    });

    it('should revert if the minimum required to swap is not greater than zero', async () => {
      const SaleFactory = await ethers.getContractFactory('DeepSquareBridge');
      await expect(SaleFactory.deploy(DPS.address, SQA.address, Eligibility.address, 0)).to.be.revertedWith(
        'DeepSquareBridge: min required to swap is not positive',
      );
    });
  });

  describe('remainingDPS', () => {
    it('should display the remaining DPS amount', async () => {
      expect(await DeepSquareBridge.remainingDPS()).to.equal(INITIAL_ROUND.sub(3000));
    });
  });

  describe('remainingSQA', () => {
    it('should display the remaining SQA amount', async () => {
      expect(await DeepSquareBridge.remainingSQA()).to.equal(INITIAL_ROUND.sub(2000));
    });
  });

  describe('swapDPSToSQA', () => {
    it.only('should let user buy SQA tokens against DPS and emit a SwapDPSToSQA event', async () => {
      const initialSold: BigNumber = await DeepSquareBridge.remainingSQA();
      await setupAccount(accounts[0], { balanceSQA: 0, balanceDPS: 1, approved: 1000, tier: 1 });

      // await agentDPS.expectBalanceOf(accounts[0], 30000);
      // await expect(DeepSquareBridge.connect(accounts[0]).swapDPSToSQA(agentDPS.unit(1000)))
      //   .to.emit(DeepSquareBridge, 'SwapDPSToSQA')
      //   .withArgs(accounts[0].address, agentSQA.unit(1000));
      //
      // await agentDPS.expectBalanceOf(accounts[0], 29000);
      // await agentSQA.expectBalanceOf(accounts[0], 1000);
      //
      // expect(await DeepSquareBridge.remainingSQA()).to.equals(
      //   initialSold.sub(await SQA.balanceOf(accounts[0].address)),
      //   'bridge state is not decremented',
      // );
    });

    it('should revert if investor is the owner', async () => {
      await expect(DeepSquareBridge.purchaseDPS(agentSQA.unit(1000))).to.be.revertedWith(
        'DeepSquareBridge: investor is the sale owner',
      );
    });

    it('should revert if investor tries to buy less that the minimum purchase', async () => {
      await expect(DeepSquareBridge.purchaseDPS(agentSQA.unit(100))).to.be.revertedWith(
        'DeepSquareBridge: amount lower than minimum',
      );
    });

    it('should revert if investor is not eligible', async () => {
      await setupAccount(accounts[0], { balanceSQA: 20000, approved: 20000, tier: 0 });

      await expect(DeepSquareBridge.connect(accounts[0]).purchaseDPS(agentSQA.unit(1000))).to.be.revertedWith(
        'DeepSquareBridge: account is not eligible',
      );
    });

    it('should revert if investor tries to buy more tokens than its tier in a single transaction', async () => {
      await setupAccount(accounts[0], { balanceSQA: 20000, approved: 20000, tier: 1 });

      // tier 1 is 15k SQA
      await expect(DeepSquareBridge.connect(accounts[0]).purchaseDPS(agentSQA.unit(16000))).to.be.revertedWith(
        'DeepSquareBridge: exceeds tier limit',
      );
    });

    it('should revert if investor tries to buy more tokens than its tier in multiple transactions', async () => {
      await setupAccount(accounts[0], { balanceSQA: 20000, approved: 20000, tier: 1 });

      await expect(DeepSquareBridge.connect(accounts[0]).purchaseDPS(agentSQA.unit(8000))).to.not.be.reverted;
      await expect(DeepSquareBridge.connect(accounts[0]).purchaseDPS(agentSQA.unit(7000))).to.not.be.reverted;
      await expect(DeepSquareBridge.connect(accounts[0]).purchaseDPS(agentSQA.unit(1000))).to.be.revertedWith(
        'DeepSquareBridge: exceeds tier limit',
      );
    });

    it('should revert if the sender has not given enough allowance', async () => {
      await setupAccount(accounts[0], { balanceSQA: 20000, approved: 500, tier: 1 });

      await expect(DeepSquareBridge.connect(accounts[0]).purchaseDPS(agentSQA.unit(1000))).to.be.revertedWith(
        'ERC20: transfer amount exceeds allowance',
      );
    });

    it('should revert if there are not enough DPS tokens left', async () => {
      // accounts[1] will buy all the tokens except 800 SQA
      await setupAccount(accounts[1], { balanceSQA: 1e8, approved: 1e8, tier: 3 });
      const remainingSQA: BigNumber = await DeepSquareBridge.convertDPStoSQA(await DeepSquareBridge.remaining());
      await DeepSquareBridge.connect(accounts[1]).purchaseDPS(remainingSQA.sub(agentSQA.unit(800)));
      expect(await DeepSquareBridge.convertDPStoSQA(await DeepSquareBridge.remaining())).to.equals(agentSQA.unit(800));

      // accounts[0] attempts to buy for 1000 SQA
      await setupAccount(accounts[0], { balanceSQA: 20000, approved: 20000, tier: 1 });

      await expect(DeepSquareBridge.connect(accounts[0]).purchaseDPS(agentSQA.unit(1000))).to.be.revertedWith(
        'DeepSquareBridge: no enough tokens remaining',
      );
    });
  });

  // describe('deliverDPS', () => {
  //   it('should deliver tokens to the investor and emit a Purchase event', async () => {
  //     await setupAccount(accounts[0], { tier: 1 });
  //     await expect(DeepSquareBridge.deliverDPS(agentSQA.unit(1000), accounts[0].address))
  //       .to.emit(DeepSquareBridge, 'Purchase')
  //       .withArgs(accounts[0].address, agentDPS.unit(2500));
  //   });
  //
  //   it('should revert if caller is not the owner', async () => {
  //     await setupAccount(accounts[0], { tier: 1 });
  //     await expect(
  //       DeepSquareBridge.connect(accounts[0]).deliverDPS(agentSQA.unit(1000), accounts[0].address),
  //     ).to.be.revertedWith('Ownable: caller is not the owner');
  //   });
  //
  //   it('should revert if beneficiary is the owner', async () => {
  //     await setupAccount(owner, { tier: 1 });
  //     await expect(DeepSquareBridge.deliverDPS(agentSQA.unit(1000), owner.address)).to.be.revertedWith(
  //       'DeepSquareBridge: investor is the sale owner',
  //     );
  //   });
  //
  //   it('should revert if beneficiary is not eligible', async () => {
  //     await expect(DeepSquareBridge.deliverDPS(agentSQA.unit(1000), accounts[0].address)).to.be.revertedWith(
  //       'DeepSquareBridge: account is not eligible',
  //     );
  //   });
  //
  //   it('should revert if beneficiary max investment is reached', async () => {
  //     await setupAccount(accounts[0], { tier: 1 });
  //
  //     await expect(DeepSquareBridge.deliverDPS(agentSQA.unit(7000), accounts[0].address))
  //       .to.emit(DeepSquareBridge, 'Purchase')
  //       .withArgs(accounts[0].address, agentDPS.unit(17500));
  //     await expect(DeepSquareBridge.deliverDPS(agentSQA.unit(8000), accounts[0].address))
  //       .to.emit(DeepSquareBridge, 'Purchase')
  //       .withArgs(accounts[0].address, agentDPS.unit(20000));
  //     await expect(DeepSquareBridge.deliverDPS(agentSQA.unit(1000), accounts[0].address)).to.be.revertedWith(
  //       'DeepSquareBridge: exceeds tier limit',
  //     );
  //   });
  //
  //   it('should revert if there are not enough DPS tokens left', async () => {
  //     await setupAccount(accounts[3], { tier: 3 });
  //     const remainingSQA: BigNumber = await DeepSquareBridge.convertDPStoSQA(await DeepSquareBridge.remaining());
  //     await DeepSquareBridge.deliverDPS(remainingSQA, accounts[3].address);
  //
  //     await setupAccount(accounts[0], { tier: 1 });
  //     await expect(DeepSquareBridge.deliverDPS(agentSQA.unit(1000), accounts[0].address)).to.be.revertedWith(
  //       'DeepSquareBridge: no enough tokens remaining',
  //     );
  //   });
  // });
  //
  // describe('close', () => {
  //   it('should transfer all its DPS to DPS owner and renounce ownership', async () => {
  //     const remaining = await DeepSquareBridge.remaining();
  //     const saleOwner = await DeepSquareBridge.owner();
  //     const initialBalance = await DPS.balanceOf(saleOwner);
  //
  //     await DeepSquareBridge.close();
  //
  //     expect(await DeepSquareBridge.owner()).to.equals(ZERO_ADDRESS);
  //     expect(await DPS.balanceOf(await DeepSquareBridge.address)).to.equals(0);
  //     expect(await DPS.balanceOf(saleOwner)).to.equals(initialBalance.add(remaining));
  //   });
  //
  //   it('should revert if the DPS contract does not have the owner function', async () => {
  //     // Configure a new Sale contract with a dummy ERC20 token
  //     const ERC20Factory = await ethers.getContractFactory('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
  //     const ERC20 = await ERC20Factory.deploy('DeepSquare no owner', 'DPS');
  //     const SaleFactory = await ethers.getContractFactory('DeepSquareBridge');
  //     DeepSquareBridge = await SaleFactory.deploy(ERC20.address, SQA.address, Eligibility.address, 40, MINIMUM_PURCHASE_SQA, 0);
  //     await Security.grantRole(ethers.utils.id('SPENDER'), DeepSquareBridge.address);
  //
  //     await expect(DeepSquareBridge.close()).to.be.revertedWith('DeepSquareBridge: unable to determine owner');
  //   });
  // });
});
