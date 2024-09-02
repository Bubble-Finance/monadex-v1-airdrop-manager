// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IMonadexV1AirdropManager {
    function addToken(address newToken) external;

    function addAirdropFund(address supportedToken,uint256 totalAmountToAirdrop)external;

    function directAirdrop(address supportedToken,address[] memory receiver,uint256 amount,bytes32[] calldata proof,uint256 index) external;

    function claimAirdrop(address supportedToken,bytes32[] calldata proof,uint256 index)external;

    function getSupportedToken (address _isSupportedToken)external view returns (bool);
    
    function getClaimedAddress(address _claimer)external view returns (bool);

    function getNewToken(uint256 TokenID) external view returns (address);

}