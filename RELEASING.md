# Releasing

Releases are cut by Nephila: it computes the next version with
[git-cliff](https://git-cliff.org/) from the
[Conventional Commit](https://www.conventionalcommits.org/) titles merged into `main`,
creates the `vX.Y.Z` tag and a GitHub Release with the notes. Nobody picks version
numbers by hand, and nothing is committed to `main` for a release: no version file, no
changelog commit.

## Commit and PR titles

PRs are squash-merged, so **the PR title becomes the commit** git-cliff reads.

| Title | Bump |
|---|---|
| `fix: ...`, `perf: ...` | patch |
| `feat: ...` | minor |
| `fix!: ...` / `feat!: ...` (or a `BREAKING CHANGE:` footer) | major |
| `chore:`, `docs:`, `build:`, `test:`, `ci:` | none |

Anything that can break apps using the library — raising the Elixir/OTP floor, removing or
renaming a public function, changing config keys, raising a dependency floor — needs `!`.
If a PR gains a breaking commit, update its title before merging.

## Where the version comes from

`mix.exs` has no hard-coded version. `get_version/0` tries, in order:

1. `EX_AWS_CONFIGURATOR_VERSION`, set when publishing.
2. `git describe --tags --long --match 'v*'`, only when `.git` sits next to `mix.exs`
   (this repo's checkout, or a Mix git dep). On the tagged commit it's the tag's version
   (`2.0.0`); N commits later it's the next patch as a dev version
   (`2.0.1-dev.N+<sha>`). Shallow clones without tags fall through.
3. `hex_metadata.config` next to `mix.exs`, which Hex writes when it installs the
   package: apps installing from Hex get the published version.
4. `0.0.0-dev`.

To check: on `v2.0.0` `mix run -e 'IO.puts Mix.Project.config()[:version]'` prints
`2.0.0`; one commit later `2.0.1-dev.1+<sha>`; with `EX_AWS_CONFIGURATOR_VERSION=9.9.9`
set, `9.9.9`.

## Publishing to Hex

Hex package owners only, from the release tag and always with the version set. Run
`mix hex.build` first: Hex rejects some packages (e.g. a dep with `override: true`) only
at build time.

```sh
git switch --detach vX.Y.Z
EX_AWS_CONFIGURATOR_VERSION=X.Y.Z mix hex.build
EX_AWS_CONFIGURATOR_VERSION=X.Y.Z mix hex.publish
```

Never publish without `EX_AWS_CONFIGURATOR_VERSION`: from an untagged commit or a clone
without tags the package would go out as `0.0.0-dev` or a dev version.

Release notes live only in the
[GitHub Releases](https://github.com/petlove/ex_aws_configurator/releases); there is no
`CHANGELOG.md`.
