# Cloudsmith CLI Setup Action

Install the [Cloudsmith CLI](https://github.com/cloudsmith-io/cloudsmith-cli) as a
**standalone binary** in GitHub Actions. No Python, no `pip`, no zipapp. 🚀

> **v3 (PoC):** this action is now a thin **composite** action. It downloads a small
> installer script hosted on a public Cloudsmith repo and runs it. The script detects
> the runner host (Linux / macOS / Windows + arch + libc), resolves the matching
> tagged release archive, downloads + extracts the prebuilt binary, puts `cloudsmith`
> on `PATH`, and authenticates. All install/auth logic lives in the installer script —
> the action just picks `install.sh` (bash) or `install.ps1` (pwsh) per runner OS.

## Usage

### Native OIDC (recommended)

The CLI exchanges the GitHub OIDC token for a short-lived Cloudsmith credential on
first use — no API key stored anywhere.

```yaml
permissions:
  id-token: write   # REQUIRED for OIDC
  contents: read

jobs:
  example:
    runs-on: ubuntu-latest   # also works on macos-* and windows-*
    env:
      CLOUDSMITH_ORG: your-namespace
      CLOUDSMITH_SERVICE_SLUG: your-service-account-slug
    steps:
      - uses: BartoszBlizniak/cloudsmith-cli-action@v3-poc
      - run: cloudsmith whoami
```

### API key

```yaml
jobs:
  example:
    runs-on: ubuntu-latest
    env:
      CLOUDSMITH_API_KEY: ${{ secrets.CLOUDSMITH_API_KEY }}
    steps:
      - uses: BartoszBlizniak/cloudsmith-cli-action@v3-poc
      - run: cloudsmith whoami
```

Authentication is performed by the CLI itself (it reads `CLOUDSMITH_API_KEY`, or
`CLOUDSMITH_ORG` + `CLOUDSMITH_SERVICE_SLUG` for native OIDC). The action does not
handle credentials directly.

## Inputs

| Input               | Description                                                              | Default |
|---------------------|--------------------------------------------------------------------------|---------|
| `cli-version`       | Cloudsmith CLI version to install, e.g. `1.19.0`, or `latest`.           | `latest` |
| `install-repo`      | Public Cloudsmith repo hosting the CLI binaries, as `OWNER/REPOSITORY`.  | `bart-demo-org-terraform/cli-binary-release-test` |
| `installer-version` | Version of the installer-script package to download from Cloudsmith.     | `v0.0.2` |
| `installer-url`     | Override: full URL to `install.sh` (Linux/macOS).                        | _(derived)_ |
| `installer-url-ps1` | Override: full URL to `install.ps1` (Windows).                           | _(derived)_ |

## How it works

```
action.yml (composite)
  ├─ Linux/macOS  ─ curl install.sh  | sh -s -- --repo <repo> --version <ver>
  └─ Windows      ─ iwr  install.ps1 ; install.ps1 -Repo <repo> -Version <ver>
                         │
                         └─ detect host → resolve tagged archive → download +
                            extract onedir bundle → add to PATH → `whoami`
```

The installer scripts ([`scripts/`](scripts/)) are the source of truth and are
published to the Cloudsmith repo as raw packages (`install.sh`, `install.ps1`).

## License

MIT — see [LICENSE](LICENSE).
