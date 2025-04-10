// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IShadowCallbackReceiver {
    function executeCallback(bytes32 guid) external;
}
