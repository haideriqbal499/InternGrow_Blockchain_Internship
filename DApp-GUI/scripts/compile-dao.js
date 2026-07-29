import fs from "node:fs";
import path from "node:path";
import solc from "solc";

const contractPath = path.resolve("contracts/DAOVoting.sol");
const source = fs.readFileSync(contractPath, "utf8");
const input = {
  language: "Solidity",
  sources: { "DAOVoting.sol": { content: source } },
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

const compiled = output.contracts["DAOVoting.sol"].DAOVoting;
fs.writeFileSync(
  path.resolve("src/dao-voting-artifact.json"),
  JSON.stringify({ abi: compiled.abi, bytecode: `0x${compiled.evm.bytecode.object}` }, null, 2)
);
console.log("Compiled DAOVoting.sol");
