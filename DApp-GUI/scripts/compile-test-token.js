import fs from "node:fs";
import path from "node:path";
import solc from "solc";

const filename = "TestGovernanceToken.sol";
const source = fs.readFileSync(path.resolve("contracts", filename), "utf8");
const input = {
  language: "Solidity",
  sources: { [filename]: { content: source } },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } }
  }
};
const output = JSON.parse(solc.compile(JSON.stringify(input)));
const errors = (output.errors ?? []).filter((item) => item.severity === "error");
if (errors.length) {
  console.error(errors.map((item) => item.formattedMessage).join("\n"));
  process.exit(1);
}
const compiled = output.contracts[filename].TestGovernanceToken;
fs.writeFileSync(
  path.resolve("src/test-token-artifact.json"),
  JSON.stringify({ abi: compiled.abi, bytecode: `0x${compiled.evm.bytecode.object}` }, null, 2)
);
console.log("Compiled TestGovernanceToken.sol");
