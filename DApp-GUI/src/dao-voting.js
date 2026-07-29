import {
  BrowserProvider, Contract, ContractFactory, formatUnits, getAddress,
  isAddress, parseUnits
} from "ethers";
import artifact from "./dao-voting-artifact.json";
import testTokenArtifact from "./test-token-artifact.json";
import "./dao-voting.css";
import "./test-token.css";

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
let dao;
let daoAddress;
let token;
let tokenAddress;
let tokenSymbol = "TOKEN";
let tokenDecimals = 18;
let walletBalance = 0n;
let allowance = 0n;
let lockedBalance = 0n;
let currentBlock = 0;
let polls = [];
let currentFilter = "all";
let toastTimer;

const shortAddress = (value, size = 5) => value ? `${value.slice(0, size + 2)}…${value.slice(-size)}` : "—";
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
}[character]));
const displayTokens = (value, digits = 4) => {
  const formatted = formatUnits(value, tokenDecimals);
  const number = Number(formatted);
  return Number.isFinite(number)
    ? new Intl.NumberFormat("en-US", { maximumFractionDigits: digits }).format(number)
    : formatted;
};

function showToast(title, message, error = false) {
  clearTimeout(toastTimer);
  $("toastTitle").textContent = title;
  $("toastMessage").textContent = message;
  $("toastIcon").textContent = error ? "!" : "✓";
  $("toast").classList.toggle("error", error);
  $("toast").classList.add("show");
  toastTimer = setTimeout(() => $("toast").classList.remove("show"), 5200);
}

function friendlyError(error) {
  const text = error?.shortMessage || error?.reason || error?.info?.error?.message || error?.message || "Transaction failed.";
  const known = {
    InvalidToken: "Use a valid ERC-20 token contract.",
    InvalidAmount: "Enter an amount greater than zero.",
    InvalidOptionCount: "A poll needs between 2 and 10 options.",
    InvalidDuration: "Duration must be between 1 and 1,000,000 blocks.",
    EmptyTitle: "Add a poll title.",
    EmptyOption: "Every poll option needs a label.",
    NoVotingPower: "Lock governance tokens before doing this.",
    AlreadyVoted: "This wallet has already voted in this poll.",
    PollExpired: "This poll's block deadline has passed.",
    PollStillOpen: "The poll cannot be closed before its deadline.",
    TokensStillCommitted: "These tokens are committed to an active poll.",
    InsufficientLockedBalance: "The unlock amount exceeds your locked balance.",
    TokenTransferFailed: "The ERC-20 transfer failed. Check your balance and approval."
  };
  for (const [key, message] of Object.entries(known)) if (text.includes(key)) return message;
  if (/user rejected|ACTION_REJECTED/i.test(text)) return "The wallet request was cancelled.";
  return text.replace(/\(action=.*$/s, "").slice(0, 190);
}

function setBusy(button, busy, label) {
  if (busy) {
    button.dataset.originalLabel = button.textContent;
    button.disabled = true;
    button.textContent = label;
  } else {
    button.textContent = button.dataset.originalLabel || button.textContent;
    button.disabled = false;
  }
}

async function connectWallet() {
  if (!window.ethereum) {
    showToast("Wallet required", "Install MetaMask or another injected Ethereum wallet.", true);
    return false;
  }
  try {
    provider = new BrowserProvider(window.ethereum);
    const accounts = await provider.send("eth_requestAccounts", []);
    signer = await provider.getSigner();
    account = getAddress(accounts[0]);
    const network = await provider.getNetwork();
    $("connectButton").textContent = shortAddress(account);
    $("networkLabel").innerHTML = `<i></i> ${escapeHtml(network.name === "unknown" ? `Chain ${network.chainId}` : network.name)}`;
    $("deployButton").disabled = false;
    $("deployTestTokenButton").disabled = false;
    if (dao) await refreshAll();
    return true;
  } catch (error) {
    showToast("Connection failed", friendlyError(error), true);
    return false;
  }
}

async function deployTestToken() {
  if (!signer && !(await connectWallet())) return;
  try {
    setBusy($("deployTestTokenButton"), true, "Confirm in wallet…");
    const factory = new ContractFactory(testTokenArtifact.abi, testTokenArtifact.bytecode, signer);
    const instance = await factory.deploy();
    showToast("Test token submitted", "Waiting for deployment confirmation…");
    await instance.waitForDeployment();
    const address = await instance.getAddress();
    $("deployToken").value = address;
    await navigator.clipboard?.writeText(address);
    showToast("TEST token deployed", `${shortAddress(address, 7)} was filled in and copied. You received 1,000,000 TEST.`);
  } catch (error) {
    showToast("Token deployment failed", friendlyError(error), true);
  } finally {
    setBusy($("deployTestTokenButton"), false);
  }
}

async function readTokenDetails(address) {
  const code = await provider.getCode(address);
  if (code === "0x") throw new Error("No token contract exists at that address.");
  const instance = new Contract(address, tokenAbi, signer);
  const [symbol, decimals] = await Promise.all([instance.symbol(), instance.decimals()]);
  return { instance, symbol, decimals: Number(decimals) };
}

async function deployDao() {
  if (!signer && !(await connectWallet())) return;
  const address = $("deployToken").value.trim();
  if (!isAddress(address)) return showToast("Invalid token", "Enter a valid ERC-20 contract address.", true);
  try {
    setBusy($("deployButton"), true, "Confirm in wallet…");
    const normalized = getAddress(address);
    await readTokenDetails(normalized);
    const factory = new ContractFactory(artifact.abi, artifact.bytecode, signer);
    const instance = await factory.deploy(normalized);
    showToast("Deployment submitted", "Waiting for network confirmation…");
    await instance.waitForDeployment();
    await attachDao(await instance.getAddress());
    showToast("DAO deployed", "LockVote is ready for governance.");
  } catch (error) {
    showToast("Deployment failed", friendlyError(error), true);
  } finally {
    setBusy($("deployButton"), false);
  }
}

async function attachDao(address = $("daoAddress").value.trim()) {
  if (!isAddress(address)) return showToast("Invalid DAO", "Enter a valid DAO contract address.", true);
  if (!signer && !(await connectWallet())) return;
  try {
    const normalized = getAddress(address);
    const code = await provider.getCode(normalized);
    if (code === "0x") throw new Error("No contract exists at that address on this network.");
    const instance = new Contract(normalized, artifact.abi, signer);
    const governanceToken = getAddress(await instance.votingToken());
    const details = await readTokenDetails(governanceToken);

    dao = instance;
    daoAddress = normalized;
    tokenAddress = governanceToken;
    token = details.instance;
    tokenSymbol = details.symbol;
    tokenDecimals = details.decimals;
    const network = await provider.getNetwork();
    localStorage.setItem(`lockVote:${network.chainId}`, normalized);

    $("daoAddress").value = normalized;
    $("setupPanel").classList.add("hidden");
    $("dashboard").classList.remove("hidden");
    $("copyDao").textContent = shortAddress(normalized, 7);
    $("copyDao").dataset.address = normalized;
    $("tokenSymbol").textContent = tokenSymbol;
    $("lockedSymbol").textContent = tokenSymbol;
    await refreshAll();
  } catch (error) {
    dao = null;
    showToast("Could not attach", friendlyError(error), true);
  }
}

function readAmount() {
  const raw = $("lockAmount").value.trim();
  if (!/^\d+(\.\d+)?$/.test(raw)) return null;
  try {
    const value = parseUnits(raw, tokenDecimals);
    return value > 0n ? value : null;
  } catch {
    return null;
  }
}

function updateActionButtons() {
  const amount = readAmount();
  const validLock = Boolean(dao && amount && amount <= walletBalance);
  $("lockButton").disabled = !validLock;
  $("lockButton").textContent = amount && allowance >= amount ? "Lock tokens" : "Approve & lock";
  $("unlockButton").disabled = !(dao && amount && amount <= lockedBalance && currentBlock > Number($("unlockButton").dataset.unlockBlock || 0));
  $("createPollButton").disabled = !dao || lockedBalance === 0n;
}

async function loadAccountState() {
  if (!dao || !account) return;
  const [balance, approved, locked, committedUntil, block] = await Promise.all([
    token.balanceOf(account),
    token.allowance(account, daoAddress),
    dao.lockedBalance(account),
    dao.unlockBlock(account),
    provider.getBlockNumber()
  ]);
  walletBalance = balance;
  allowance = approved;
  lockedBalance = locked;
  currentBlock = block;
  $("currentBlock").textContent = new Intl.NumberFormat().format(block);
  $("walletBalance").textContent = `${displayTokens(balance)} ${tokenSymbol}`;
  $("approvedAmount").textContent = `${displayTokens(approved)} ${tokenSymbol}`;
  $("lockedAmount").textContent = displayTokens(locked);
  $("unlockAt").textContent = committedUntil === 0n ? "Not committed" : `Block ${new Intl.NumberFormat().format(committedUntil)}`;
  $("unlockButton").dataset.unlockBlock = committedUntil.toString();
  updateActionButtons();
}

async function lockTokens() {
  const amount = readAmount();
  if (!amount || amount > walletBalance) return;
  try {
    setBusy($("lockButton"), true, "Working…");
    if (allowance < amount) {
      const approval = await token.approve(daoAddress, amount);
      showToast("Approval submitted", "Confirming token allowance…");
      await approval.wait();
    }
    const transaction = await dao.lockTokens(amount);
    showToast("Lock submitted", "Confirming your voting power…");
    await transaction.wait();
    $("lockAmount").value = "";
    showToast("Tokens locked", `${displayTokens(amount)} ${tokenSymbol} added to your voting power.`);
    await refreshAll();
  } catch (error) {
    showToast("Lock failed", friendlyError(error), true);
  } finally {
    setBusy($("lockButton"), false);
    updateActionButtons();
  }
}

async function unlockTokens() {
  const amount = readAmount();
  if (!amount || amount > lockedBalance) return;
  try {
    setBusy($("unlockButton"), true, "Confirm in wallet…");
    const transaction = await dao.unlockTokens(amount);
    await transaction.wait();
    $("lockAmount").value = "";
    showToast("Tokens unlocked", `${displayTokens(amount)} ${tokenSymbol} returned to your wallet.`);
    await refreshAll();
  } catch (error) {
    showToast("Unlock failed", friendlyError(error), true);
  } finally {
    setBusy($("unlockButton"), false);
    updateActionButtons();
  }
}

function pollFormValues() {
  const title = $("pollTitle").value.trim();
  const description = $("pollDescription").value.trim();
  const options = $("pollOptions").value.split(/\r?\n/).map((value) => value.trim()).filter(Boolean);
  const duration = Number($("durationBlocks").value);
  return { title, description, options, duration };
}

async function createPoll() {
  const { title, description, options, duration } = pollFormValues();
  if (!title) return showToast("Title required", "Give this poll a concise title.", true);
  if (options.length < 2 || options.length > 10) return showToast("Options required", "Add between 2 and 10 options, one per line.", true);
  if (!Number.isInteger(duration) || duration < 1 || duration > 1_000_000) return showToast("Invalid duration", "Choose 1 to 1,000,000 blocks.", true);
  try {
    setBusy($("createPollButton"), true, "Confirm in wallet…");
    const transaction = await dao.createPoll(title, description, options, duration);
    showToast("Poll submitted", "Waiting for network confirmation…");
    await transaction.wait();
    $("pollTitle").value = "";
    $("pollDescription").value = "";
    $("pollOptions").value = "";
    showToast("Poll created", "The proposal is now open for token-weighted voting.");
    await refreshAll();
  } catch (error) {
    showToast("Creation failed", friendlyError(error), true);
  } finally {
    setBusy($("createPollButton"), false);
    updateActionButtons();
  }
}

async function loadPolls() {
  if (!dao) return;
  currentBlock = await provider.getBlockNumber();
  const count = Number(await dao.pollCount());
  const first = Math.max(1, count - 49);
  const ids = Array.from({ length: count ? count - first + 1 : 0 }, (_, index) => count - index);
  polls = await Promise.all(ids.map(async (id) => {
    const [poll, result, voted] = await Promise.all([
      dao.getPoll(id),
      dao.getOptions(id),
      dao.hasVoted(id, account)
    ]);
    return {
      id,
      creator: poll.creator,
      title: poll.title,
      description: poll.description,
      startBlock: Number(poll.startBlock),
      deadlineBlock: Number(poll.deadlineBlock),
      active: poll.active,
      totalVotingPower: poll.totalVotingPower,
      voterCount: Number(poll.voterCount),
      names: result[0],
      votes: result[1],
      voted
    };
  }));
  renderPolls();
}

function renderPolls() {
  const visible = polls.filter((poll) => {
    const open = poll.active && currentBlock <= poll.deadlineBlock;
    return currentFilter === "all" || (currentFilter === "open" ? open : !open);
  });
  if (!visible.length) {
    $("pollList").innerHTML = `<div class="empty-state"><span>◇</span><h3>No ${currentFilter === "all" ? "" : currentFilter} polls</h3><p>${polls.length ? "Try another status filter." : "Lock tokens and open the first community decision."}</p></div>`;
    return;
  }
  $("pollList").innerHTML = visible.map((poll) => {
    const open = poll.active && currentBlock <= poll.deadlineBlock;
    const expiredNeedsClose = poll.active && currentBlock > poll.deadlineBlock;
    const total = poll.totalVotingPower;
    const options = poll.names.map((name, optionId) => {
      const votes = poll.votes[optionId];
      const percentage = total > 0n ? Number((votes * 10_000n) / total) / 100 : 0;
      const disabled = !open || poll.voted || lockedBalance === 0n;
      return `<button class="option" data-poll="${poll.id}" data-option="${optionId}" ${disabled ? "disabled" : ""}>
        <span class="option-fill" style="width:${percentage}%"></span>
        <span class="option-content"><span class="option-name">${escapeHtml(name)}</span><span class="option-result">${displayTokens(votes)} ${escapeHtml(tokenSymbol)} · ${percentage.toFixed(1)}%</span></span>
      </button>`;
    }).join("");
    const blocksLeft = Math.max(0, poll.deadlineBlock - currentBlock);
    return `<article class="poll-card">
      <div class="poll-top"><div><span class="poll-id">PROPOSAL #${poll.id}</span><h3>${escapeHtml(poll.title)}</h3><p class="poll-description">${escapeHtml(poll.description || "No description provided.")}</p></div><span class="poll-state ${open ? "" : "closed"}">${open ? "● OPEN" : "CLOSED"}</span></div>
      <div class="poll-meta"><span>Created by <b>${shortAddress(poll.creator)}</b></span><span>Deadline <b>block ${new Intl.NumberFormat().format(poll.deadlineBlock)}</b></span><span><b>${poll.voterCount}</b> voter${poll.voterCount === 1 ? "" : "s"}</span></div>
      <div class="options">${options}</div>
      <div class="poll-footer"><span>${poll.voted ? "✓ You voted" : open ? `${new Intl.NumberFormat().format(blocksLeft)} blocks remaining · vote weight: ${displayTokens(lockedBalance)} ${escapeHtml(tokenSymbol)}` : `Final voting power: ${displayTokens(total)} ${escapeHtml(tokenSymbol)}`}</span>${expiredNeedsClose ? `<button class="close-button" data-close="${poll.id}">Finalize poll</button>` : ""}</div>
    </article>`;
  }).join("");
}

async function vote(pollId, optionId, button) {
  try {
    setBusy(button, true, "Confirm vote…");
    const transaction = await dao.vote(pollId, optionId);
    showToast("Vote submitted", "Your token-weighted vote is being confirmed.");
    await transaction.wait();
    showToast("Vote recorded", "This wallet cannot vote again on the same poll.");
    await refreshAll();
  } catch (error) {
    showToast("Vote failed", friendlyError(error), true);
  } finally {
    setBusy(button, false);
  }
}

async function closePoll(pollId, button) {
  try {
    setBusy(button, true, "Finalizing…");
    const transaction = await dao.closePoll(pollId);
    await transaction.wait();
    showToast("Poll finalized", "The expired poll is now marked closed.");
    await loadPolls();
  } catch (error) {
    showToast("Finalize failed", friendlyError(error), true);
  } finally {
    setBusy(button, false);
  }
}

async function refreshAll() {
  if (!dao) return;
  try {
    await Promise.all([loadAccountState(), loadPolls()]);
    renderPolls();
  } catch (error) {
    showToast("Refresh failed", friendlyError(error), true);
  }
}

$("connectButton").addEventListener("click", connectWallet);
$("deployTestTokenButton").addEventListener("click", deployTestToken);
$("deployButton").addEventListener("click", deployDao);
$("attachButton").addEventListener("click", () => attachDao());
$("refreshButton").addEventListener("click", refreshAll);
$("lockButton").addEventListener("click", lockTokens);
$("unlockButton").addEventListener("click", unlockTokens);
$("createPollButton").addEventListener("click", createPoll);
$("lockAmount").addEventListener("input", updateActionButtons);
$("maxButton").addEventListener("click", () => {
  $("lockAmount").value = formatUnits(walletBalance, tokenDecimals);
  updateActionButtons();
});
$("copyDao").addEventListener("click", async () => {
  if (!daoAddress) return;
  await navigator.clipboard.writeText(daoAddress);
  showToast("Address copied", daoAddress);
});
document.querySelectorAll(".filter").forEach((button) => button.addEventListener("click", () => {
  currentFilter = button.dataset.filter;
  document.querySelectorAll(".filter").forEach((item) => item.classList.toggle("active", item === button));
  renderPolls();
}));
$("pollList").addEventListener("click", (event) => {
  const option = event.target.closest("[data-option]");
  if (option) return vote(Number(option.dataset.poll), Number(option.dataset.option), option);
  const closer = event.target.closest("[data-close]");
  if (closer) closePoll(Number(closer.dataset.close), closer);
});

if (window.ethereum) {
  window.ethereum.on?.("accountsChanged", () => location.reload());
  window.ethereum.on?.("chainChanged", () => location.reload());
  provider = new BrowserProvider(window.ethereum);
  provider.send("eth_accounts", []).then(async (accounts) => {
    if (!accounts.length) return;
    await connectWallet();
    const network = await provider.getNetwork();
    const saved = localStorage.getItem(`lockVote:${network.chainId}`);
    if (saved) await attachDao(saved);
  });
}
