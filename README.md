# bootstrap-scripts

Public installer scripts for developer tools and private CLIs.
These scripts are designed to be hosted publicly while installing source code from private repositories using your local `git` client (SSH auth) and `cargo`.

## Usage

```sh
export REPO=owner/private-cli
curl -fsSL https://raw.githubusercontent.com/fradesa/bootstrap-scripts/main/install-rust-cli.sh | sh
```
