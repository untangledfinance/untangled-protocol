# Contract address

abis:

```
https://github.com/untangledfinance/untangled-protocol/tree/rebuild/newProxyAndRebased/deployments/alfajores_v3
```

## Main updates

Removed
`LoanRepaymentRouter`
Merged into `LoanKernel`

Removed `TGEMintedIncreasing`
=> Temporarily removed `Sot Auction Type` on UI

Removed `DistributionAccessor` Merged into `SecuritizationPoolValueService`

Removed all Pool Diamond logics, Merged into `Pool`

Removed `startCycle` function, need to remove from FE side

SOT/JOT now only long sale, remove `ClosingTime` when issuing sot/jot, need to remove on FE side

## Function updates

### Securitization Manager

Before

```
function setUpTGEForSOT(
        TGEParam memory tgeParam,
        NewRoundSaleParam memory saleParam,
        IncreasingInterestParam memory increasingInterestParam
    )
```

After

```
function setUpTGEForSOT(TGEParam memory tgeParam, uint256 interestRate)
```

Before

```
function setUpTGEForJOT(
        TGEParam memory tgeParam,
        NewRoundSaleParam memory saleParam,
        uint256 initialJOTAmount
    )
```

After

```
 function setUpTGEForJOT(TGEParam memory tgeParam, uint256 initialJOTAmount)
```

## BE events update

Removed `TokenPurchased` from `SecuritizationManager` => Need to handle the Chart in Pool detail in Investor app

Need to generate go file again from new ABIs

```
- Add Loan
- Asset repay
- Asset risk score update
- Asset writeoff
- CollectErc20 asset
- Debt ceiling Update
- Min first loss Update
- Pool deployed -
- Set riskscore
- Set pool linked wallet
- Setup Jot - [changed]
- Setup Sot - [changed]
- Start cycle - [changed to UpdateInterestRateSot]
- TGE info update
- Withdraw ERC20
- RedeemOrder
- CancelOrder
- SetRedeemDisabled
- DisburseOrder
- PreDistribute
```
