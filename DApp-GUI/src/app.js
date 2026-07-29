import {
  BrowserProvider, Contract, ContractFactory, formatEther, formatUnits,
  getAddress, isAddress, parseEther, parseUnits, ZeroAddress
} from "ethers";
import artifact from "./contract-artifact.json";
import "./styles.css";

const $ = (id) => document.getElementById(id);
const tokenAbi = [
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)"
];

let provider;
let signer;
let account;
let contract;
let mode = "eth";
let tokenInfo = null;
let toastTimer;
let previewTimer;
let tokenTimer;

const short = (address, size = 4) => address ? `${address.slice(0, size + 2)}…${address.slice(-size)}` : "—";
const compactAmount = (value, decimals = 4) => {
  const number = Number(value);
  if (!Number.isFinite(number)) return value;
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: decimals }).format(number);
};

function showToast(title, message, isError = false) {
  clearTimeout(toastTimer);
  $("toastTitle").textContent = title;
  $("toastMessage").textContent = message;
  $("toastIcon").textContent = isError ? "!" : "✓";
  $("toast").classList.toggle("error", isError);
  $("toast").classList.add("show");
  toastTimer = setTimeout(() => $("toast").classList.remove("show"), 5500);
}

function friendlyError(error) {
  let text = error?.shortMessage || error?.reason || error?.info?.error?.message || error?.message || "The transaction could not be completed.";
  const messages = {
    NoRecipients: "Add at least one recipient.",
    TooManyRecipients: "This contract accepts up to 200 recipients per batch.",
    InvalidRecipient: "One of the recipient addresses is invalid.",
    InvalidToken: "The token address is not a compatible ERC-20 contract.",
    ZeroAmount: "The amount is too small to split across these recipients.",
    InsufficientTokenBalance: "Your token balance is lower than this distribution total.",
    InsufficientAllowance: "Approve the token amount before sending.",
    TransferFailed: "A recipient transfer failed, so the whole batch was safely reverted."
  };
  for (const [key, message] of Object.entries(messages)) if (text.includes(key)) return message;
  if (/user rejected|ACTION_REJECTED/i.test(text)) return "The wallet request was cancelled.";
  return text.replace(/\(action=.*$/s, "").slice(0, 190);
}

function setBusy(button, busy, pendingLabel) {
  if (busy) {
    button.dataset.label = button.textContent;
    button.disabled = true;
    button.textContent = pendingLabel;
  } else {
    button.textContent = button.dataset.label || button.textContent;
    button.disabled = false;
  }
}

async function connectWallet() {
  if (!window.ethereum) {
    showToast("MetaMask required", "Install a browser wallet to deploy and use Airflow.", true);
    return false;
  }
  try {
    provider = new BrowserProvider(window.ethereum);
    const accounts = await provider.send("eth_requestAccounts", []);
    signer = await provider.getSigner();
    account = getAddress(accounts[0]);
    const network = await provider.getNetwork();
    $("walletLabel").textContent = short(account, 5);
    $("sourceInitial").textContent = account.slice(2, 3).toUpperCase();
    $("networkName").textContent = network.name === "unknown" ? `Chain ${network.chainId}` : network.name;
    $("deployButton").disabled = false;
    if (contract) await refreshAll();
    return true;
  } catch (error) {
    showToast("Connection failed", friendlyError(error), true);
    return false;
  }
}

async function deployContract() {
  if (!signer && !(await connectWallet())) return;
  try {
    setBusy($("deployButton"), true, "Confirm in wallet…");
    const factory = new ContractFactory(artifact.abi, artifact.bytecode, signer);
    const instance = await factory.deploy();
    showToast("Deployment submitted", "Waiting for network confirmation…");
    await instance.waitForDeployment();
    const address = await instance.getAddress();
    await attachContract(address);
    showToast("Airflow deployed", `Contract ready at ${short(address, 7)}.`);
  } catch (error) {
    showToast("Deployment failed", friendlyError(error), true);
  } finally {
    setBusy($("deployButton"), false);
  }
}

async function attachContract(address = $("contractAddress").value.trim()) {
  if (!isAddress(address)) return showToast("Invalid contract", "Enter a valid Ethereum contract address.", true);
  if (!signer && !(await connectWallet())) return;
  try {
    address = getAddress(address);
    const code = await provider.getCode(address);
    if (code === "0x") throw new Error("No contract exists at that address on this network.");
    const instance = new Contract(address, artifact.abi, signer);
    await instance.MAX_RECIPIENTS();
    contract = instance;
    localStorage.setItem("airflowContractAddress", address);
    $("contractAddress").value = address;
    $("copyContract").textContent = short(address, 6);
    $("copyContract").dataset.address = address;
    $("setupPanel").classList.add("hidden");
    $("appPanel").classList.remove("hidden");
    await refreshAll();
  } catch (error) {
    contract = null;
    showToast("Could not attach", friendlyError(error), true);
  }
}

function parseRecipients() {
  const raw = $("recipientInput").value.trim();
  const entries = raw ? raw.split(/[\s,;]+/).filter(Boolean) : [];
  const addresses = [];
  const invalid = [];
  const duplicates = [];
  const seen = new Set();
  entries.forEach((value, index) => {
    if (!isAddress(value) || getAddress(value) === ZeroAddress) return invalid.push(index + 1);
    const address = getAddress(value);
    const key = address.toLowerCase();
    if (seen.has(key)) duplicates.push(index + 1);
    else { seen.add(key); addresses.push(address); }
  });
  return { entries, addresses, invalid, duplicates };
}

function readAmount() {
  const raw = $("totalAmount").value.trim();
  if (!raw || !/^\d+(\.\d+)?$/.test(raw)) return null;
  try {
    const decimals = mode === "eth" ? 18 : tokenInfo?.decimals;
    if (decimals === undefined) return null;
    const value = mode === "eth" ? parseEther(raw) : parseUnits(raw, decimals);
    return value > 0n ? value : null;
  } catch { return null; }
}

function currentSplit() {
  const recipients = parseRecipients().addresses;
  const total = readAmount();
  if (!total || recipients.length === 0) return null;
  const each = total / BigInt(recipients.length);
  if (each === 0n) return null;
  return { recipients, total, each, sent: each * BigInt(recipients.length) };
}

function displayUnits(value) {
  const decimals = mode === "eth" ? 18 : tokenInfo?.decimals ?? 18;
  return compactAmount(formatUnits(value, decimals), 7);
}

function updatePreview() {
  const parsed = parseRecipients();
  const count = parsed.addresses.length;
  $("recipientCount").textContent = `${count} / 200`;
  $("summaryRecipients").textContent = `${count} wallet${count === 1 ? "" : "s"}`;
  $("stackCount").textContent = count;

  const validation = $("validationLine");
  if (parsed.invalid.length) {
    validation.className = "validation-line error";
    validation.innerHTML = `<span>!</span> Invalid address at position ${parsed.invalid[0]}`;
  } else if (parsed.duplicates.length) {
    validation.className = "validation-line error";
    validation.innerHTML = `<span>!</span> Duplicate address at position ${parsed.duplicates[0]}`;
  } else if (count > 200) {
    validation.className = "validation-line error";
    validation.innerHTML = "<span>!</span> Batch exceeds the 200 recipient safety limit";
  } else if (count) {
    validation.className = "validation-line valid";
    validation.innerHTML = `<span>✓</span> ${count} unique, valid wallet${count === 1 ? "" : "s"}`;
  } else {
    validation.className = "validation-line";
    validation.innerHTML = "<span>○</span> Waiting for recipient addresses";
  }

  const split = currentSplit();
  const symbol = mode === "eth" ? "ETH" : tokenInfo?.symbol || "TOKEN";
  $("perRecipient").textContent = split ? `${displayUnits(split.each)} ${symbol}` : "—";
  $("summaryPer").textContent = split ? `${displayUnits(split.each)} ${symbol}` : "—";
  $("summaryTotal").textContent = split ? `${displayUnits(split.sent)} ${symbol}` : "—";
  const formValid = Boolean(contract && account && split && !parsed.invalid.length && !parsed.duplicates.length && count <= 200);

  if (mode === "token") {
    const approved = Boolean(split && tokenInfo && tokenInfo.allowance >= split.sent);
    $("approveButton").classList.toggle("hidden", !split || approved);
    $("approveButton").disabled = !formValid || !tokenInfo || tokenInfo.balance < (split?.sent ?? 0n);
    $("sendButton").disabled = !formValid || !approved || tokenInfo.balance < split.sent;
  } else {
    $("approveButton").classList.add("hidden");
    $("sendButton").disabled = !formValid;
  }

  clearTimeout(previewTimer);
  $("gasEstimate").textContent = formValid ? "Estimating…" : "Complete the form";
  if (formValid) previewTimer = setTimeout(estimateGas, 500);
}

async function estimateGas() {
  const split = currentSplit();
  if (!contract || !split) return;
  try {
    const gas = mode === "eth"
      ? await contract.airdropEth.estimateGas(split.recipients, { value: split.total })
      : await contract.airdropToken.estimateGas(tokenInfo.address, split.recipients, split.total);
    $("gasEstimate").textContent = `${new Intl.NumberFormat().format(gas)} gas units`;
  } catch (error) {
    const message = friendlyError(error);
    $("gasEstimate").textContent = message.length > 44 ? "Wallet checks required" : message;
  }
}

async function loadTokenInfo() {
  tokenInfo = null;
  const address = $("tokenAddress").value.trim();
  if (!isAddress(address) || !provider || !account) {
    $("tokenSymbol").textContent = "ERC-20";
    $("tokenHint").textContent = "Enter a token address to read its symbol, decimals, balance, and allowance.";
    updatePreview();
    return;
  }
  try {
    const normalized = getAddress(address);
    const code = await provider.getCode(normalized);
    if (code === "0x") throw new Error("This address is not a token contract.");
    const token = new Contract(normalized, tokenAbi, signer);
    const spender = await contract.getAddress();
    const [symbol, decimals, balance, allowance] = await Promise.all([
      token.symbol(), token.decimals(), token.balanceOf(account), token.allowance(account, spender)
    ]);
    tokenInfo = { address: normalized, symbol, decimals: Number(decimals), balance, allowance, contract: token };
    $("tokenSymbol").textContent = symbol;
    $("amountSymbol").textContent = symbol;
    $("summaryAsset").textContent = symbol;
    $("tokenHint").textContent = `Balance: ${compactAmount(formatUnits(balance, decimals), 6)} ${symbol} · Approved: ${compactAmount(formatUnits(allowance, decimals), 6)} ${symbol}`;
  } catch (error) {
    $("tokenHint").textContent = friendlyError(error);
    showToast("Token unavailable", friendlyError(error), true);
  }
  updatePreview();
}

async function approveToken() {
  const split = currentSplit();
  if (!tokenInfo || !split) return;
  try {
    setBusy($("approveButton"), true, "Confirm approval…");
    const transaction = await tokenInfo.contract.approve(await contract.getAddress(), split.sent);
    showToast("Approval submitted", "Waiting for network confirmation…");
    await transaction.wait();
    tokenInfo.allowance = await tokenInfo.contract.allowance(account, await contract.getAddress());
    showToast("Token approved", "Airflow can now distribute this amount.");
    updatePreview();
  } catch (error) {
    showToast("Approval failed", friendlyError(error), true);
  } finally { setBusy($("approveButton"), false); updatePreview(); }
}

async function sendAirdrop() {
  const split = currentSplit();
  if (!contract || !split) return;
  try {
    setBusy($("sendButton"), true, "Confirm in wallet…");
    const transaction = mode === "eth"
      ? await contract.airdropEth(split.recipients, { value: split.total })
      : await contract.airdropToken(tokenInfo.address, split.recipients, split.total);
    showToast("Airdrop submitted", `Sending to ${split.recipients.length} wallets…`);
    await transaction.wait();
    showToast("Airdrop complete", "Every transfer was confirmed atomically.");
    await refreshAll();
  } catch (error) {
    showToast("Airdrop failed", friendlyError(error), true);
  } finally { setBusy($("sendButton"), false); updatePreview(); }
}

async function loadStatus() {
  if (!contract) return;
  try {
    const [, ethDistributed, , airdropCount] = await contract.getStatus();
    $("dropCount").textContent = airdropCount.toString();
    $("ethVolume").textContent = compactAmount(formatEther(ethDistributed), 4);
  } catch (error) { showToast("Refresh failed", friendlyError(error), true); }
}

async function loadActivity() {
  if (!contract || !provider) return;
  try {
    const current = await provider.getBlockNumber();
    const from = Math.max(0, current - 5000);
    const [ethEvents, tokenEvents] = await Promise.all([
      contract.queryFilter(contract.filters.EthAirdropCompleted(), from, current),
      contract.queryFilter(contract.filters.TokenAirdropCompleted(), from, current)
    ]);
    const events = [...ethEvents, ...tokenEvents].sort((a, b) => b.blockNumber - a.blockNumber).slice(0, 7);
    $("activityList").innerHTML = events.length ? events.map((event) => {
      const isEth = event.fragment.name === "EthAirdropCompleted";
      const count = event.args.recipients.toString();
      return `<div class="activity-item"><span class="activity-icon">↗</span><div><strong>${isEth ? "ETH" : "Token"} airdrop · ${count} wallets</strong><p>Sender ${short(event.args.sender, 5)} · atomic distribution confirmed</p></div><time>Block ${event.blockNumber}</time></div>`;
    }).join("") : '<p class="empty">Your completed distributions will appear here.</p>';
  } catch { $("activityList").innerHTML = '<p class="empty">Activity is unavailable on this RPC endpoint.</p>'; }
}

async function refreshAll() {
  await Promise.all([loadStatus(), loadActivity()]);
  if (mode === "token" && $("tokenAddress").value) await loadTokenInfo();
  updatePreview();
}

function setMode(nextMode) {
  mode = nextMode;
  document.querySelectorAll(".mode-tab").forEach((button) => button.classList.toggle("active", button.dataset.mode === mode));
  $("tokenField").classList.toggle("hidden", mode !== "token");
  $("amountSymbol").textContent = mode === "eth" ? "ETH" : tokenInfo?.symbol || "TOKEN";
  $("summaryAsset").innerHTML = mode === "eth" ? '<span class="mini-asset">◆</span> Native ETH' : (tokenInfo?.symbol || "ERC-20 token");
  updatePreview();
}

$("connectButton").addEventListener("click", connectWallet);
$("deployButton").addEventListener("click", deployContract);
$("attachButton").addEventListener("click", () => attachContract());
$("refreshButton").addEventListener("click", refreshAll);
$("recipientInput").addEventListener("input", updatePreview);
$("totalAmount").addEventListener("input", updatePreview);
$("approveButton").addEventListener("click", approveToken);
$("sendButton").addEventListener("click", sendAirdrop);
$("tokenAddress").addEventListener("input", () => {
  clearTimeout(tokenTimer);
  tokenTimer = setTimeout(loadTokenInfo, 500);
});
document.querySelectorAll(".mode-tab").forEach((button) => button.addEventListener("click", () => setMode(button.dataset.mode)));
$("copyContract").addEventListener("click", async () => {
  const address = $("copyContract").dataset.address;
  if (address) { await navigator.clipboard.writeText(address); showToast("Address copied", address); }
});

if (window.ethereum) {
  window.ethereum.on?.("accountsChanged", () => location.reload());
  window.ethereum.on?.("chainChanged", () => location.reload());
  provider = new BrowserProvider(window.ethereum);
  provider.send("eth_accounts", []).then(async (accounts) => {
    if (!accounts.length) return;
    await connectWallet();
    const saved = localStorage.getItem("airflowContractAddress");
    if (saved) await attachContract(saved);
  });
}

updatePreview();
