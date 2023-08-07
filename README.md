# UNIV3_SIMPLE_ROUTER

 Simple router to perform buys against UniswapV3 liquidity pools

 RouterProcessorV3 and UniversalRouter are complicated to use, specially for bots so I decided to develop my own approach, more simple and gas efficient trading directly against the liquidity pool contract

[![Solidity testing CI using hardhat]( https://github.com/MiguelGGMM/UNIV3_SIMPLE_ROUTER/actions/workflows/hardhat-test-pnpm.js.yml/badge.svg)]( https://github.com/MiguelGGMM/UNIV3_SIMPLE_ROUTER/actions/workflows/hardhat-test-pnpm.js.yml) 
[![Coverage Status](https://coveralls.io/repos/github/MiguelGGMM/UNIV3_SIMPLE_ROUTER/badge.svg?branch=master)](https://coveralls.io/github/MiguelGGMM/UNIV3_SIMPLE_ROUTER?branch=master)

 ## INSTRUCTIONS

 ```
 pnpm install
 ```
 
 Using ```pnpm run``` you can check the commands you will need to test your smart contract and run linter and prettier for solidity or typescript files

## DEPLOYMENT

If you want to test deployments you have to include your pk on .pk.example and remove the .example \
Also edit the deploy.js script and the deploy command to include the network you want to deploy against, this network has to be previously configured in hardhat.config.ts \
Check https://hardhat.org/hardhat-runner/docs/guides/deploying if you are lost here

## Verification
 
You have to include your API KEY if you desire to test the verification plugin, also you have to configure the networks you want to use, if your constructor receives complex arguments you also will have to create a file
Everything is explained here: https://hardhat.org/hardhat-runner/plugins/nomicfoundation-hardhat-verify

## GAS REPORTER

We are using the gas reporter included in hardhat and codechecks integration for github actions, for this you have to add your repo here https://app.codechecks.io/, copy the code and add it as a secret for your repository named CC_SECRET, check the codecheks.yml and the .yml for github actions depending on your branch name changes could be needed. \
https://github.com/codechecks/docs/blob/master/getting-started.md \
Diff parameters can be configured in hardhat.config.ts so will end in a failure if the gas spent rises too much.


