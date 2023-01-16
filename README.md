<p align="center">
  <a href="https://github.com/pooltogether/pooltogether--brand-assets">
    <img src="https://github.com/pooltogether/pooltogether--brand-assets/blob/977e03604c49c63314450b5d432fe57d34747c66/logo/pooltogether-logo--purple-gradient.png?raw=true" alt="PoolTogether Brand" style="max-width:100%;" width="400">
  </a>
</p>

<br />

# PoolTogether - Liquidator Contracts

> TODO: Coveralls tag, coverage

[![built-with openzeppelin](https://img.shields.io/badge/built%20with-OpenZeppelin-3677FF)](https://docs.openzeppelin.com/)
[![GPLv3 license](https://img.shields.io/badge/License-GPLv3-blue.svg)](http://perso.crans.org/besson/LICENSE.html)

<strong>Have questions or want the latest news?</strong>
<br/>Join the PoolTogether Discord or follow us on Twitter:

[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://pooltogether.com/discord)
[![Twitter](https://badgen.net/badge/icon/twitter?icon=twitter&label)](https://twitter.com/PoolTogether_)

**Documentation**<br>
https://v4.docs.pooltogether.com

**Deployments**<br>

- [Ethereum](https://v4.docs.pooltogether.com/protocol/deployments/mainnet#mainnet)
- [Polygon](https://v4.docs.pooltogether.com/protocol/deployments/mainnet#polygon)
- [Avalanche](https://v4.docs.pooltogether.com/protocol/deployments/mainnet#avalanche)
- [Optimism](https://v4.docs.pooltogether.com/protocol/deployments/mainnet/#optimism)

## Getting Started

The repo can be cloned from Github for contributions.

```sh
git clone https://github.com/pooltogether/liquidator
```

### Installation

To install with [**Foundry**](https://github.com/gakonst/foundry):

```sh
forge install pooltogether/liquidator
```

### Testing

To run tests:

```sh
forge test
```

To run a specific test contract:

```sh
forge test --mc <test contract name>
```

To run coverage:

```sh
forge coverage
```

### Deployment

> TODO:

### Notes

`uint112` - Uniswap V2 limits to this as a safe maximum. For an 18 decimal token, this is more than a million billion tokens (1e15)
