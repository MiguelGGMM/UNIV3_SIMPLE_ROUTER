import { ethers, network } from "hardhat";
import {
  /* IDEXRouter, */
  TemplateToken,
  TemplateToken__factory,
  PancakeRouter,
} from "../typechain-types";
import { Addressable, BigNumberish, TransactionReceipt } from "ethers";
import { expect } from "chai";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { BN } from "bn.js";

const gasLimit = "5000000";
//const gasPrice = "5000000000";

/* const ZERO_ADDRESS = `0x0000000000000000000000000000000000000000`;
const DEAD_ADDRESS = `0x000000000000000000000000000000000000dEaD`; */

let _TemplateToken: TemplateToken;
let _IDEXRouter: PancakeRouter; //| IDEXRouter;
let accounts: HardhatEthersSigner[];
let _owner: HardhatEthersSigner;

//Unique way make eth-gas-reporter work fine
const dexContractName = "PancakeRouter";

const debug = process.env.DEBUG_TEST == "1";

const getAccountBalance = async (account: string) => {
  const balance = await ethers.provider.getBalance(account);
  return ethers.formatUnits(balance, "ether");
};

const BN2 = (x: BigNumberish) => new BN(x.toString());
const toWei = (value: BigNumberish) => ethers.parseEther(value.toString());
/* const fromWei = (value: BigNumberish, fixed: number = 2) =>
  parseFloat(ethers.formatUnits(value, "ether")).toFixed(fixed); */

const getBlockTimestamp = async () => {
  return (await ethers.provider.getBlock("latest"))?.timestamp;
};

/* const getBlockNumber = async () => {
  return (await ethers.provider.getBlock("latest"))?.number;
}; */

const increaseDays = async (days: number) => {
  await increase(86400 * days);
};

const increase = async (duration: number) => {
  return new Promise((resolve /* reject */) => {
    network.provider
      .request({
        method: "evm_increaseTime",
        params: [duration],
      })
      .finally(() => {
        network.provider
          .request({
            method: "evm_mine",
            params: [],
          })
          .finally(() => {
            resolve(undefined);
          });
      });
  });
};

const log = (message: string) => {
  if (debug) {
    console.log(`\t[DEBUG] ${message}`);
  }
};

describe("TemplateToken", function () {
  async function deployment() {
    const templateToken = await ethers.deployContract("TemplateToken", {
      //gasPrice: gasPrice,
      gasLimit: "20000000",
    });
    await templateToken.waitForDeployment();
    log(
      `TemplateToken successfully deployed: ${
        templateToken.target
      } (by: ${await templateToken.owner()})`,
    );
    // Contracts are deployed using the first signer/account by default
    const _accounts = await ethers.getSigners();
    return { templateToken, _accounts };
  }

  async function attachContracts() {
    if (process.env.ROUTER) {
      _IDEXRouter = await ethers.getContractAt(
        dexContractName,
        process.env.ROUTER,
      );

      log(`Contracts attached: DEX router`);
      log(`Addresses: ${_IDEXRouter.target}`);
      return true;
    }
    return false;
  }

  const buyDEX = async (_eth: BigNumberish, _account: HardhatEthersSigner) => {
    log(`Buying ${_eth} ether...`);
    const _IDEXRouter2 = await ethers.getContractAt(
      dexContractName,
      _IDEXRouter.target,
      _account,
    );
    const _tx =
      await _IDEXRouter2.swapExactETHForTokensSupportingFeeOnTransferTokens(
        0,
        [await _IDEXRouter.WETH(), _TemplateToken.target],
        _account,
        parseInt(((await getBlockTimestamp()) ?? 0).toString()) + 3600,
        {
          value: toWei(_eth),
          //gasPrice: gasPrice,
          gasLimit: gasLimit,
        },
      );
    log(`Buy performed, ${_eth} ether`);
    return _tx;
  };

  const sellDEX = async (
    _nTokens: BigNumberish,
    _account: HardhatEthersSigner,
  ) => {
    log(`Approving tokens ${_nTokens}`);
    TemplateToken__factory.connect(
      _TemplateToken.target.toString(),
      _account,
    ).approve(_IDEXRouter.target, _nTokens);
    log(`Selling... ${_nTokens.toString()} tokens`);
    const _IDEXRouter2 = await ethers.getContractAt(
      dexContractName,
      _IDEXRouter.target,
      _account,
    ); //IDEXRouter__factory.connect(_IDEXRouter.target.toString(), _account);
    const _tx =
      await _IDEXRouter2.swapExactTokensForETHSupportingFeeOnTransferTokens(
        _nTokens.toString(),
        0,
        [_TemplateToken.target, await _IDEXRouter2.WETH()],
        _account,
        parseInt(((await getBlockTimestamp()) ?? 0).toString()) + 3600,
        {
          //value: toWei("0.05"),
          //gasPrice: gasPrice,
          gasLimit: gasLimit,
        },
      );
    log(`Sell performed: ${_nTokens.toString()} tokens`);
    return _tx;
  };

  const getDevSigner = async () =>
    await ethers.getImpersonatedSigner(await _TemplateToken.owner());

  describe("Deployment", function () {
    it("We check environment variables config", async function () {
      log(`Environment ROUTER: ${process.env.ROUTER}`);
      expect([process.env.ROUTER]).to.satisfy(
        (s: (string | undefined)[]) =>
          s.every((_s) => _s != undefined && _s != ""),
        "Environment variables ROUTER can not be empty or undefined",
      );
    });

    it("We attach already existing contracts we have to use", async function () {
      expect(await attachContracts()).to.be.equals(
        true,
        "An error happened attaching already existing contracts",
      );
    });

    it("We attach contracts that have been deployed", async function () {
      const { ...args } = await deployment();
      _TemplateToken = args.templateToken;
      accounts = args._accounts;
      _owner = accounts[0]; //depends... check

      log(`Contracts deployed: TemplateToken`);
      log(`Addresses: ${_TemplateToken.target}`);
      log(`Deployer address: ${_owner.address}`);
      log(
        `Full list of addresses: \n${accounts
          .map((_a) => `\t\t${_a.address}`)
          .join(",\n")}`,
      );
      expect(_TemplateToken.target).to.satisfy(
        (s: string | Addressable) => s != undefined && s != "",
      );
    });
  });

  describe("Add liquidity and checks", function () {
    it("We add the liquidity", async function () {
      const ownerBalBefore = await getAccountBalance(_owner.address);

      //Send eth to contract, send token, open trade
      const ownerBal = await _TemplateToken.balanceOf(
        await _TemplateToken.owner(),
      );
      await _TemplateToken.transfer(
        _TemplateToken.target.toString(),
        BN2(ownerBal).mul(BN2(95)).div(BN2(100)).toString(),
      );

      const contractBalBefore = await _TemplateToken.balanceOf(
        _TemplateToken.target.toString(),
      );
      await _TemplateToken.openTrading({ value: toWei(1) });
      const contractBalAfter = await _TemplateToken.balanceOf(
        _TemplateToken.target.toString(),
      );

      const ownerBalAfter = await getAccountBalance(_owner.address);
      //expect(transactionResponse).not.to.be.reverted;
      log(
        `Owner ${_owner.address} bal before: ${ownerBalBefore}, bal after: ${ownerBalAfter}`,
      );
      log(
        `Contract ${_TemplateToken.target.toString()} bal before: ${contractBalBefore}, bal after: ${contractBalAfter}`,
      );
      expect(parseInt(ownerBalBefore) - parseInt(ownerBalAfter)).to.be.gte(
        1,
        "1 ether was added to liq, so we have to confirm the balance difference",
      );
    });
  });

  describe("Transactions checks", function () {
    it("Owner transaction without fee applied", async function () {
      const [ownerBeforeBalance, userBeforeBalance] = await Promise.all([
        BN2(await _TemplateToken.balanceOf(_owner)),
        BN2(await _TemplateToken.balanceOf(accounts[1])),
      ]);
      const sumBefore = ownerBeforeBalance.add(userBeforeBalance).toString();
      await _TemplateToken.transfer(
        accounts[1],
        ownerBeforeBalance.div(BN2(100)).toString(),
      );
      const [ownerAfterBalance, userAfterBalance] = await Promise.all([
        BN2(await _TemplateToken.balanceOf(_owner)),
        BN2(await _TemplateToken.balanceOf(accounts[1])),
      ]);
      const sumAfter = ownerAfterBalance.add(userAfterBalance).toString();
      expect(sumAfter).to.satisfy(
        (afterBalance: string) => BN2(afterBalance).eq(BN2(sumBefore)),
        "Total amount has to be the same than before because no fees are applied",
      );
    });

    it("User transaction with fee applied", async function () {
      const [ownerBeforeBalance, userBeforeBalance] = await Promise.all([
        BN2(await _TemplateToken.balanceOf(accounts[1])),
        BN2(await _TemplateToken.balanceOf(accounts[2])),
      ]);
      const sumBefore = ownerBeforeBalance.add(userBeforeBalance).toString();
      const _templateToken = TemplateToken__factory.connect(
        _TemplateToken.target.toString(),
        accounts[1],
      );
      await _templateToken.transfer(
        accounts[2].address.toLowerCase(),
        ownerBeforeBalance.div(BN2(100)).toString(),
      );
      const [ownerAfterBalance, userAfterBalance] = await Promise.all([
        BN2(await _TemplateToken.balanceOf(accounts[1])),
        BN2(await _TemplateToken.balanceOf(accounts[2])),
      ]);
      const sumAfter = ownerAfterBalance.add(userAfterBalance).toString();
      expect(sumAfter).to.satisfy(
        (afterBalance: string) => BN2(afterBalance).lt(BN2(sumBefore)),
        "Total amount has to be lower than before because of fees applied",
      );
    });
  });

  describe("Buys checks", function () {
    it("Perform buys, with all the accounts, should work", async function () {
      const txs = await Promise.all(
        accounts.map((_account) => buyDEX("0.01", _account)),
      );
      const txsR = await Promise.all(txs.map((_tx) => _tx.wait()));
      expect(txsR).to.satisfy((_txs: TransactionReceipt[]) =>
        _txs.every((_tx) => _tx.status == 1),
      );
    });
  });

  describe("Sells checks", function () {
    it("Perform sell should work", async function () {
      const tokensSellBefore = await _TemplateToken.balanceOf(accounts[1]);
      await sellDEX(BN2(tokensSellBefore).div(BN2(10)).toString(), accounts[1]);
      const tokensSellAfter = await _TemplateToken.balanceOf(accounts[1]);
      expect(BN2(tokensSellBefore).sub(BN2(tokensSellAfter))).to.be.gte(
        BN2(tokensSellBefore).div(BN2(10)),
      ); //.not.to.be.reverted("Transaction should not revert")
    });

    it("Increase time 1 day", async function () {
      const blockTimestampBefore = await getBlockTimestamp();
      await increaseDays(1);
      const blockTimestampAfter = await getBlockTimestamp();
      const _diff = (blockTimestampAfter ?? 0) - (blockTimestampBefore ?? 0);
      log(
        `Block timestamp before-after: ${blockTimestampBefore}-${blockTimestampAfter} (${_diff})`,
      );
      expect(_diff).to.be.gte(3600 * 24);
    });

    it("Perform sell should work", async function () {
      const tokensSellBefore = await _TemplateToken.balanceOf(accounts[1]);
      await sellDEX(BN2(tokensSellBefore).div(BN2(10)).toString(), accounts[1]);
      const tokensSellAfter = await _TemplateToken.balanceOf(accounts[1]);
      expect(BN2(tokensSellBefore).sub(BN2(tokensSellAfter))).to.be.gte(
        BN2(tokensSellBefore).div(BN2(10)),
      );
    });
  });

  describe("Auxiliary functions", function () {
    it("Force swapback", async function () {
      const txs = await TemplateToken__factory.connect(
        _TemplateToken.target.toString(),
        await getDevSigner(),
      ).manualSwap({ gasLimit: gasLimit });
      const txsR = await txs.wait();
      expect(txsR).to.satisfy((_tx: TransactionReceipt) => _tx.status == 1); //expect().not.to.be.reverted;
    });

    it("Clear stuck", async function () {
      const _tt = await TemplateToken__factory.connect(
        _TemplateToken.target.toString(),
        await getDevSigner(),
      );

      const buyTax = parseInt((await _tt._buyTax()).toString());
      const sellTax = parseInt((await _tt._sellTax()).toString());

      await TemplateToken__factory.connect(
        _TemplateToken.target.toString(),
        await getDevSigner(),
      ).reduceFee(2);

      const buyTax2 = parseInt((await _tt._buyTax()).toString());
      const sellTax2 = parseInt((await _tt._sellTax()).toString());

      expect([
        [buyTax, sellTax],
        [buyTax2, sellTax2],
      ]).to.satisfy(
        (taxes: number[][]) =>
          taxes[0][0] == taxes[1][0] + 2 && taxes[0][1] == taxes[1][1] + 2,
      );
    });
  });
});
