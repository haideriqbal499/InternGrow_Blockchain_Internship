// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Airdrop {

    event AirdropCompleted(uint totalRecipients, uint amountPerRecipient);

    function airdrop(address[] calldata recipients) external payable {

        require(recipients.length > 0, "No recipients");

        uint amount = msg.value / recipients.length;

        for(uint i = 0; i < recipients.length; i++) {

            payable(recipients[i]).transfer(amount);

        }

        emit AirdropCompleted(recipients.length, amount);
    }
}
