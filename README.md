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

![image](https://github.com/MiguelGGMM/UNIV3_SIMPLE_ROUTER/assets/104460442/8acd495c-d614-43e5-a32b-d83fa9a44621)

You can see the avg column is empty, if you need that include your CMC key in .cmc.example and remove the .example
CI=true in enviroment variables is required so it generates the required json output in gasReporterOutput.json

If you want see previous output locally you have to run ```pnpm run codechecks```

## Coverage
 
Coveralls integration for github actions is also included, for this you have to add your repo here https://coveralls.io/repos and add a secret for your repository COVERALLS_REPO_TOKEN and set there your repo token, there you will also find a link in order to add your coverage badge in your readme. You can also configure coverage decrease thresholds for failure so if someone ruins the coverage the merge will be blocked.

![image](https://github.com/MiguelGGMM/UNIV3_SIMPLE_ROUTER/assets/104460442/d76e3bf7-d520-4971-b2b5-b2b5a212e01f)

Locally once you run ```pnpm run coverage``` a report summary will be generated where you can see the % of lines covered for your tests etc, also folder named coverage will be generated with an index.html file inside, if you click it you can check the coverage report similar to the summary you saw after execution but you can also navigate using your browser and check inside each contract which lines are covered which not and how much times each line.

![image](https://github.com/MiguelGGMM/UNIV3_SIMPLE_ROUTER/assets/104460442/e4477d24-3cc0-45d6-be22-1577a5b1024e)

