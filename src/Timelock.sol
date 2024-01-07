// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

contract Timelock is TimelockController {

    // `minDelay`: initial minimum delay in seconds for operations
    // `proposers`: accounts to be granted proposer and canceller roles
    // `executors`: accounts to be granted executor role
    // `admin`: optional account to be granted admin role; disable with zero address

    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin) TimelockController(minDelay, proposers, executors, msg.sender){}

    
}
