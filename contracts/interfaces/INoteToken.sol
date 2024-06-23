pragma solidity 0.8.19;

interface INoteToken {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint256);

    function transfer(address to, uint256 currencyAmount) external returns (bool);

    function mint(address to, uint256 currencyAmount) external;

    function redeem(address user, uint256 currencyAmount) external;

    function distributeIncome(uint256 currencyAmount) external;

    function calcUserIncome(address user) external view returns (uint256);

    function pool() external view returns (address);
}
