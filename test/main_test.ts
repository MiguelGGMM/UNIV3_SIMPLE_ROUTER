import { ethers /* network */ } from "hardhat";
import {
  SimpleRouterV3,
  SimpleRouterV3__factory,
  IWETH__factory,
  IERC20__factory,
} from "../typechain-types";
import { Addressable, BigNumberish /* TransactionReceipt */ } from "ethers";
import { expect } from "chai";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { BN } from "bn.js";

//const gasLimit = "5000000";
//const gasPrice = "5000000000";

/* const ZERO_ADDRESS = `0x0000000000000000000000000000000000000000`;
const DEAD_ADDRESS = `0x000000000000000000000000000000000000dEaD`; */

const BUY_TEST_ARRAY: string[][] = [
  ["LINK", "0x514910771AF9Ca656af840dff83E8264EcF986CA"],
  ["TETHER", "0xdAC17F958D2ee523a2206206994597C13D831ec7"],
  ["PEPE", "0x6982508145454Ce325dDbE47a25d4ec3d2311933"],
];

const WETH = process.env.WETH ?? "";
const UNIV3_FACTORY_ETH = process.env.UNIV3_FACTORY_ETH ?? "";
const debug = process.env.DEBUG_TEST == "1";
const debugsolidity = process.env.DEBUG_SOLIDITY == "1";

let _SimpleRouterV3: SimpleRouterV3;
let accounts: HardhatEthersSigner[];
let _owner: HardhatEthersSigner;

// const getAccountBalance = async (account: string) => {
//   const balance = await ethers.provider.getBalance(account);
//   return ethers.formatUnits(balance, "ether");
// };

const BN2 = (x: BigNumberish) => new BN(x.toString());
const toWei = (value: BigNumberish) => ethers.parseEther(value.toString());

// const fromWei = (value: BigNumberish, fixed: number = 2) =>
//   parseFloat(ethers.formatUnits(value, "ether")).toFixed(fixed);

// const getBlockTimestamp = async () => {
//   return (await ethers.provider.getBlock("latest"))?.timestamp;
// };

// const getBlockNumber = async () => {
//   return (await ethers.provider.getBlock("latest"))?.number;
// };

// const increaseDays = async (days: number) => {
//   await increase(86400 * days);
// };

// const increase = async (duration: number) => {
//   return new Promise((resolve /* reject */) => {
//     network.provider
//       .request({
//         method: "evm_increaseTime",
//         params: [duration],
//       })
//       .finally(() => {
//         network.provider
//           .request({
//             method: "evm_mine",
//             params: [],
//           })
//           .finally(() => {
//             resolve(undefined);
//           });
//       });
//   });
// };

const log = (message: string) => {
  if (debug) {
    console.log(`\t[DEBUG] ${message}`);
  }
};

describe("SimpleRouterV3", function () {
  async function deployment() {
    const simpleRouterV3 = await ethers.deployContract(
      "SimpleRouterV3",
      [WETH, debugsolidity],
      {
        //gasPrice: gasPrice,
        gasLimit: "20000000",
      },
    );
    await simpleRouterV3.waitForDeployment();
    log(
      `SimpleRouterV3 successfully deployed: ${
        simpleRouterV3.target
      } (by: ${await simpleRouterV3.owner()})`,
    );
    // Contracts are deployed using the first signer/account by default
    const _accounts = await ethers.getSigners();
    return { simpleRouterV3, _accounts };
  }

  // const getDevSigner = async () =>
  //   await ethers.getImpersonatedSigner(await _SimpleRouterV3.owner());

  describe("Deployment", function () {
    it("We attach contracts that have been deployed", async function () {
      const { ...args } = await deployment();
      _SimpleRouterV3 = args.simpleRouterV3;
      accounts = args._accounts;
      _owner = accounts[0]; //depends... check

      log(`Contracts deployed: SimpleRouterV3`);
      log(`Addresses: ${_SimpleRouterV3.target}`);
      log(`Deployer address: ${_owner.address}`);
      log(
        `Full list of addresses: \n${accounts
          .map((_a) => `\t\t${_a.address}`)
          .join(",\n")}`,
      );
      expect(_SimpleRouterV3.target).to.satisfy(
        (s: string | Addressable) => s != undefined && s != "",
      );
    });
  });

  for (const BUY_TEST_DATA of BUY_TEST_ARRAY) {
    const BUY_TEST_CURRENT = BUY_TEST_DATA[1];

    describe(`Buys checks [${BUY_TEST_DATA[0]} (${BUY_TEST_DATA[1]})]`, function () {
      it("Perform buy with ETH, should work", async function () {
        for (const acc of accounts.slice(2, 4)) {
          const __SimpleRouterV3 = SimpleRouterV3__factory.connect(
            _SimpleRouterV3.target.toString(),
            acc,
          );
          const amountOut = await __SimpleRouterV3.calcAmountReceived(
            UNIV3_FACTORY_ETH,
            BUY_TEST_CURRENT,
            WETH,
            toWei("1"),
          );

          for (let _i = 0; _i < 2; _i++) {
            let amountOutReal = BN2(
              await IERC20__factory.connect(BUY_TEST_CURRENT, acc).balanceOf(
                acc,
              ),
            );

            const tx = await __SimpleRouterV3.performBuyTokenETH(
              UNIV3_FACTORY_ETH,
              BUY_TEST_CURRENT,
              0,
              { value: toWei("1") },
            );
            const txsr = await tx.wait();

            amountOutReal = BN2(
              (
                await IERC20__factory.connect(BUY_TEST_CURRENT, acc).balanceOf(
                  acc,
                )
              ).toString(),
            ).sub(amountOutReal);

            log(
              `Amount expected ${amountOut}, amount received ${amountOutReal}, acc ${acc.address}`,
            );
            const checkTx = txsr?.status && txsr.status == 1;
            const checkMin = amountOutReal.gte(
              BN2(amountOut).mul(BN2(99)).div(BN2(100)),
            );
            const checkMax = amountOutReal
              .mul(BN2(99))
              .div(BN2(100))
              .lte(BN2(amountOut));

            expect(checkTx).to.satisfy(
              (chk: boolean) => chk,
              `Transaction failed for account ${acc.address}`,
            );
            expect(checkMin).to.satisfy(
              (chk: boolean) => chk,
              `Less tokens than expected received for account ${acc.address}`,
            );
            expect(checkMax).to.satisfy(
              (chk: boolean) => chk,
              `More tokens than expected received for account ${acc.address}`,
            );
          }
        }
      });

      it("Perform buy with token (WETH), should work", async function () {
        for (const acc of accounts.slice(2, 4)) {
          const __SimpleRouterV3 = SimpleRouterV3__factory.connect(
            _SimpleRouterV3.target.toString(),
            acc,
          );
          const amountOut = await __SimpleRouterV3.calcAmountReceived(
            UNIV3_FACTORY_ETH,
            BUY_TEST_CURRENT,
            WETH,
            toWei("1"),
          );

          for (let _i = 0; _i < 2; _i++) {
            await IWETH__factory.connect(WETH, acc).deposit({
              value: toWei("1"),
            });
            await IERC20__factory.connect(WETH, acc).approve(
              __SimpleRouterV3.target.toString(),
              toWei("1"),
            );

            let amountOutReal = BN2(
              await IERC20__factory.connect(BUY_TEST_CURRENT, acc).balanceOf(
                acc,
              ),
            );

            const tx = await __SimpleRouterV3.performBuyToken(
              UNIV3_FACTORY_ETH,
              BUY_TEST_CURRENT,
              WETH,
              toWei("1"),
              0,
            );
            const txsr = await tx.wait();

            amountOutReal = BN2(
              (
                await IERC20__factory.connect(BUY_TEST_CURRENT, acc).balanceOf(
                  acc,
                )
              ).toString(),
            ).sub(amountOutReal);

            log(
              `Amount expected ${amountOut}, amount received ${amountOutReal}, acc ${acc.address}`,
            );
            const checkTx = txsr?.status && txsr.status == 1;
            const checkMin = amountOutReal.gte(
              BN2(amountOut).mul(BN2(99)).div(BN2(100)),
            );
            const checkMax = amountOutReal
              .mul(BN2(99))
              .div(BN2(100))
              .lte(BN2(amountOut));

            expect(checkTx).to.satisfy(
              (chk: boolean) => chk,
              `(TOKEN) Transaction failed for account ${acc.address}`,
            );
            expect(checkMin).to.satisfy(
              (chk: boolean) => chk,
              `(TOKEN) Less tokens than expected received for account ${acc.address}`,
            );
            expect(checkMax).to.satisfy(
              (chk: boolean) => chk,
              `(TOKEN) More tokens than expected received for account ${acc.address}`,
            );
          }
        }
      });
    });

    describe(`Buys checks with slip [${BUY_TEST_DATA[0]} (${BUY_TEST_DATA[1]})]`, function () {
      it("Perform buy with ETH and slip 99, should work", async function () {
        for (const acc of accounts.slice(2, 4)) {
          const __SimpleRouterV3 = SimpleRouterV3__factory.connect(
            _SimpleRouterV3.target.toString(),
            acc,
          );
          const amountOut = await __SimpleRouterV3.calcAmountReceived(
            UNIV3_FACTORY_ETH,
            BUY_TEST_CURRENT,
            WETH,
            toWei("1"),
          );

          for (let _i = 0; _i < 2; _i++) {
            let amountOutReal = BN2(
              await IERC20__factory.connect(BUY_TEST_CURRENT, acc).balanceOf(
                acc,
              ),
            );

            const amountMin = BN2(amountOut)
              .mul(BN2(99))
              .div(BN2(100))
              .toString();
            const tx = await __SimpleRouterV3.performBuyTokenETH(
              UNIV3_FACTORY_ETH,
              BUY_TEST_CURRENT,
              amountMin,
              { value: toWei("1") },
            );
            const txsr = await tx.wait();

            amountOutReal = BN2(
              (
                await IERC20__factory.connect(BUY_TEST_CURRENT, acc).balanceOf(
                  acc,
                )
              ).toString(),
            ).sub(amountOutReal);

            log(
              `Amount expected ${amountOut}, amount received ${amountOutReal}, acc ${acc.address}`,
            );
            const checkTx = txsr?.status && txsr.status == 1;
            const checkMin = amountOutReal.gte(
              BN2(amountOut).mul(BN2(99)).div(BN2(100)),
            );
            const checkMax = amountOutReal
              .mul(BN2(99))
              .div(BN2(100))
              .lte(BN2(amountOut));

            expect(checkTx).to.satisfy(
              (chk: boolean) => chk,
              `Transaction failed for account ${acc.address}`,
            );
            expect(checkMin).to.satisfy(
              (chk: boolean) => chk,
              `Less tokens than expected received for account ${acc.address}`,
            );
            expect(checkMax).to.satisfy(
              (chk: boolean) => chk,
              `More tokens than expected received for account ${acc.address}`,
            );
          }
        }
      });

      it("Perform buy with ETH and slip 101, should NOT work", async function () {
        for (const acc of accounts.slice(2, 4)) {
          const __SimpleRouterV3 = SimpleRouterV3__factory.connect(
            _SimpleRouterV3.target.toString(),
            acc,
          );
          const amountOut = await __SimpleRouterV3.calcAmountReceived(
            UNIV3_FACTORY_ETH,
            BUY_TEST_CURRENT,
            WETH,
            toWei("1"),
          );

          for (let _i = 0; _i < 2; _i++) {
            const amountMin = BN2(amountOut)
              .mul(BN2(101))
              .div(BN2(100))
              .toString();
            await expect(
              __SimpleRouterV3.performBuyTokenETH(
                UNIV3_FACTORY_ETH,
                BUY_TEST_CURRENT,
                amountMin,
                { value: toWei("1") },
              ),
            ).to.be.revertedWith("Slippage error");
          }
        }
      });

      it("Perform buy with token (WETH) and slip 99, should work", async function () {
        for (const acc of accounts.slice(2, 4)) {
          const __SimpleRouterV3 = SimpleRouterV3__factory.connect(
            _SimpleRouterV3.target.toString(),
            acc,
          );
          const amountOut = await __SimpleRouterV3.calcAmountReceived(
            UNIV3_FACTORY_ETH,
            BUY_TEST_CURRENT,
            WETH,
            toWei("1"),
          );

          for (let _i = 0; _i < 2; _i++) {
            await IWETH__factory.connect(WETH, acc).deposit({
              value: toWei("1"),
            });
            await IERC20__factory.connect(WETH, acc).approve(
              __SimpleRouterV3.target.toString(),
              toWei("1"),
            );

            let amountOutReal = BN2(
              await IERC20__factory.connect(BUY_TEST_CURRENT, acc).balanceOf(
                acc,
              ),
            );

            const amountMin = BN2(amountOut)
              .mul(BN2(99))
              .div(BN2(100))
              .toString();
            const tx = await __SimpleRouterV3.performBuyToken(
              UNIV3_FACTORY_ETH,
              BUY_TEST_CURRENT,
              WETH,
              toWei("1"),
              amountMin,
            );
            const txsr = await tx.wait();

            amountOutReal = BN2(
              (
                await IERC20__factory.connect(BUY_TEST_CURRENT, acc).balanceOf(
                  acc,
                )
              ).toString(),
            ).sub(amountOutReal);

            log(
              `Amount expected ${amountOut}, amount received ${amountOutReal}, acc ${acc.address}`,
            );
            const checkTx = txsr?.status && txsr.status == 1;
            const checkMin = amountOutReal.gte(
              BN2(amountOut).mul(BN2(99)).div(BN2(100)),
            );
            const checkMax = amountOutReal
              .mul(BN2(99))
              .div(BN2(100))
              .lte(BN2(amountOut));

            expect(checkTx).to.satisfy(
              (chk: boolean) => chk,
              `(TOKEN) Transaction failed for account ${acc.address}`,
            );
            expect(checkMin).to.satisfy(
              (chk: boolean) => chk,
              `(TOKEN) Less tokens than expected received for account ${acc.address}`,
            );
            expect(checkMax).to.satisfy(
              (chk: boolean) => chk,
              `(TOKEN) More tokens than expected received for account ${acc.address}`,
            );
          }
        }
      });

      it("Perform buy with token (WETH) and slip 101, should NOT work", async function () {
        for (const acc of accounts.slice(2, 4)) {
          const __SimpleRouterV3 = SimpleRouterV3__factory.connect(
            _SimpleRouterV3.target.toString(),
            acc,
          );
          const amountOut = await __SimpleRouterV3.calcAmountReceived(
            UNIV3_FACTORY_ETH,
            BUY_TEST_CURRENT,
            WETH,
            toWei("1"),
          );

          for (let _i = 0; _i < 2; _i++) {
            await IWETH__factory.connect(WETH, acc).deposit({
              value: toWei("1"),
            });
            await IERC20__factory.connect(WETH, acc).approve(
              __SimpleRouterV3.target.toString(),
              toWei("1"),
            );

            const amountMin = BN2(amountOut)
              .mul(BN2(101))
              .div(BN2(100))
              .toString();
            await expect(
              __SimpleRouterV3.performBuyToken(
                UNIV3_FACTORY_ETH,
                BUY_TEST_CURRENT,
                WETH,
                toWei("1"),
                amountMin,
              ),
            ).to.be.revertedWith("Slippage error");
          }
        }
      });
    });
  }
});
