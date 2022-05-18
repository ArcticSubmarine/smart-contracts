import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { SQA_TOTAL_SUPPLY } from '../lib/constants';
import SpenderSecurity from '../typings/SpenderSecurity';
import Square from '../typings/Square';
import IERC20Metadata from '../typings/openzeppelin/IERC20Metadata';
import { createERC20Agent, ERC20Agent } from './testing/ERC20Agent';
import { randomInt } from './testing/random';
import setup from './testing/setup';

describe.only('Square', async () => {
  let owner: SignerWithAddress;
  let accounts: SignerWithAddress[];
  let SQA: Square;
  let agentSQA: ERC20Agent;
  let Security: SpenderSecurity;

  beforeEach(async () => {
    ({ owner, accounts, Security } = await setup());

    const SquareFactory = await ethers.getContractFactory('Square');
    SQA = (await SquareFactory.deploy(Security.address)) as unknown as IERC20Metadata;
    agentSQA = await createERC20Agent(SQA);
  });

  describe('on initialization', () => {
    it('should mint 210M SQA to the deployer', async () => {
      await agentSQA.expectBalanceOf(owner, SQA_TOTAL_SUPPLY);
    });

    it('should promote the deployer to be the contract owner', async () => {
      expect(await SQA.owner()).to.equals(owner.address);
    });
  });

  describe('transfer', () => {
    describe('if the sender is the contract owner', () => {
      it('should let him transfer its own SQA to another account', async () => {
        const initialBalance = await SQA.balanceOf(owner.address);
        const amount = agentSQA.unit(randomInt(10, 50) * 1000);
        await agentSQA.transfer(accounts[0], amount);
        await agentSQA.expectBalanceOf(accounts[0], amount);
        await agentSQA.expectBalanceOf(owner, initialBalance.sub(amount));
      });
    });
  });

  describe('transferFrom', () => {
    describe('the account is the owner', () => {
      it('should let the owner transfer SQA from other accounts with their consent', async () => {
        const amount = agentSQA.unit(randomInt(10, 50) * 1000);
        await agentSQA.transfer(accounts[0], amount);

        await SQA.connect(accounts[0]).approve(owner.address, amount);
        expect(await SQA.allowance(accounts[0].address, owner.address)).to.equals(amount);

        await SQA.transferFrom(accounts[0].address, accounts[1].address, amount);
        expect(await SQA.allowance(accounts[0].address, owner.address)).to.equals(0);
        await agentSQA.expectBalanceOf(accounts[0], 0);
        await agentSQA.expectBalanceOf(accounts[1], amount);
      });

      it('should prevent the owner from transferring SQA from other accounts with their consent', async () => {
        const amount = agentSQA.unit(randomInt(10, 50) * 1000);
        await agentSQA.transfer(accounts[0], amount);
        await expect(SQA.transferFrom(accounts[0].address, accounts[1].address, amount)).to.revertedWith(
          'ERC20: insufficient allowance',
        );
      });
    });
  });

  describe('setSecurity', () => {
    it('should revert if caller is not the owner', async () => {
      const initialSecurity = await SQA.security();
      await expect(SQA.connect(accounts[0]).setSecurity(accounts[1].address)).to.revertedWith(
        'Ownable: caller is not the owner',
      );
      expect(await SQA.security()).to.equals(initialSecurity);
    });

    it('should add a new security (to change transfer rules)', async () => {
      await expect(SQA.setSecurity(accounts[1].address));
      expect(await SQA.security()).to.equals(accounts[1].address);
    });
  });
});
