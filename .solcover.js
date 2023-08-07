module.exports = {
  client: require("ganache"),
  providerOptions: {
    port: 8545,
    hostname: "127.0.0.1",
  },  
  skipFiles: [
    "Libraries",
    "UniswapV3"
  ]  
};
