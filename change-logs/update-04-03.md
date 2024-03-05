# Contract address

abis:

```
https://github.com/untangledfinance/untangled-protocol/tree/rebuild/newProxyAndRebased/deployments/alfajores_v3
```

## Main updates

Removed
`setValidator`
From `SecuritizationManager`

Grant `VALIDATOR_ROLE` via Pool by `POOL Admin`:

```
await securitizationPoolContract.connect(poolAdminSigner).grantRole(VALIDATOR_ROLE, validator.address);
```
