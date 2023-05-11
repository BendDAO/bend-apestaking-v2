module.exports = {
  silent: true,
  measureStatementCoverage: true,
  measureFunctionCoverage: true,
  skipFiles: ["interfaces", "test", "misc/interfaces", "misc/PoolViewer.sol"],
  configureYulOptimizer: true,
};
