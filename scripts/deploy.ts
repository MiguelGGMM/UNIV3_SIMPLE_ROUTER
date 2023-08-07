import { ethers } from "hardhat";
import _ from "lodash";

async function main() {
  console.log(
    `Deploying using parameters: \n\t${_.filter(
      Object.keys(process.env),
      (_o) => ["NAME", "SYMBOL", "PAIR", "STABLE", "ROUTER"].includes(_o),
    ).map((_o) => `${_o}:${process.env[_o]}\n\t`)}`,
  );

  const simpleRouterV3 = await ethers.deployContract("SimpleRouterV3", [
    process.env.WETH,
    false,//process.env.DEBUG_SOLIDITY == "1",
  ]);
  await simpleRouterV3.waitForDeployment();
  console.log(
    `SimpleRouterV3 successfully deployed: ${simpleRouterV3.target}`,
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
