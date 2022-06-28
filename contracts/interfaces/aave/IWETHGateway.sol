// SPDX-License-Identifier: MIT

interface IWETHGateway {
  function depositETH(
    address pool,
    address onBehalfOf,
    uint16 referralCode
  ) external payable;

  function withdrawETH(
    address pool,
    uint256 amount,
    address onBehalfOf
  ) external;
}
