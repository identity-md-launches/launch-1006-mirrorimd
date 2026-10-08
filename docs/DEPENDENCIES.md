# Vendored dependencies

All dependency files are copied unchanged from the worker's provided local mirrors. No symlinks, submodules, package managers, or remote imports are used during builds.

| Directory | Mirror package version | Included material | License |
| --- | --- | --- | --- |
| `lib/openzeppelin-contracts` | `openzeppelin-solidity` 5.7.0 | ERC20, IERC20, IERC20Metadata, IERC6093, Context, LICENSE | MIT |
| `lib/forge-std` | forge-std 1.16.2 | Complete `src/` and both license files | MIT OR Apache-2.0 |

The OpenZeppelin ERC20 source header identifies its last update as v5.5.0. Package version here records the local mirror's package.json, not a separately fetched release or an assertion of an independent audit. Only the five required Solidity files were copied from that mirror. Forge standard library code is used for tests and the deployment script, not by the production token.

`docs/dependency-checksums.sha256` pins the exact delivered dependency bytes. Verify from the repository root:

```sh
sha256sum --check docs/dependency-checksums.sha256
```

Upstream project identities: [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) and [Forge Standard Library](https://github.com/foundry-rs/forge-std). These links are informational; neither is accessed during build or test.
