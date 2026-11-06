# Vendored dependencies

The project builds and tests without downloading dependencies. All files below are regular repository files, not submodules. Build artifacts and compiler binaries are not dependencies shipped by this project.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0) | `v5.1.0` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`, and `LICENSE` | MIT |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Upstream `src/` and both license files; used by tests only | MIT or Apache-2.0 |

The files were copied unchanged from these releases. OpenZeppelin files came from the release-tagged paths on `raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v5.1.0/`. Forge Standard Library came from the tagged archive at `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`; its archive SHA-256 was `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.

`DEPENDENCIES.sha256` records the SHA-256 of each included source and license file. Verify the local copies from the repository root with:

```sh
sha256sum --check DEPENDENCIES.sha256
```

The remappings resolve exclusively to `lib/` inside this repository. Only the five OpenZeppelin Solidity files are part of the token's dependency graph. Forge Standard Library is test infrastructure and is not part of the deployed token.
