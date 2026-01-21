# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| Latest release | :white_check_mark: |
| Development (main) | :white_check_mark: |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities by emailing the repository owner directly.

Include the following information:

- Type of vulnerability
- Full path to the affected file(s)
- Location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce
- Proof-of-concept or exploit code (if possible)
- Impact assessment

## Security Measures

This repository implements several security measures:

- **Secret Encryption**: All secrets are encrypted using SOPS with Age encryption
- **Secret Scanning**: GitHub secret scanning is enabled with push protection
- **Code Scanning**: CodeQL analysis runs on all PRs and pushes
- **Dependency Updates**: Renovate automatically updates dependencies
- **Pinned Actions**: GitHub Actions are pinned to commit SHAs
- **Trivy Scanning**: Container and configuration security scanning

## Secrets Management

- Never commit unencrypted secrets
- All `*.sops.yaml` files must be encrypted
- The `age.key` file must never be committed (gitignored)
- Use `task sops:encrypt` before committing secret files
