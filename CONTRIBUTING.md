# Contributing to TuringOne Community

Thank you for your interest in contributing to **TuringOne Community**.

We welcome contributions that help improve the Community Edition, including bug fixes, documentation improvements, usability enhancements, and technical improvements.

## How to Contribute

### 1. Fork the Repository

Fork the repository to your own GitHub account.

Then clone your fork:

```bash
git clone https://github.com/YOUR_USERNAME/turingone-ui-community.git
cd turingone-ui-community
```

### 2. Create a Branch

Create a dedicated branch for your changes.

Examples:

```bash
git checkout -b feature/improve-dashboard
```

```bash
git checkout -b fix/login-issue
```

Recommended branch prefixes:

* `feature/` – new functionality
* `fix/` – bug fixes
* `docs/` – documentation
* `refactor/` – code refactoring
* `test/` – tests

Do not work directly on the `main` branch.

## 3. Make Your Changes

Please keep your changes focused on a specific issue or improvement.

Before submitting your contribution:

* Follow the existing project architecture and coding conventions.
* Avoid unnecessary changes to unrelated files.
* Reuse existing components and services where possible.
* Do not commit generated files unless required.
* Do not include credentials, passwords, API keys, tokens, certificates, or `.env` files.
* Do not include confidential, proprietary, customer, or internal company information.

## 4. Test Your Changes

Before creating a Pull Request, make sure that:

* The application builds successfully.
* Existing functionality continues to work.
* Your changes do not introduce new errors.
* Relevant automated tests pass.
* New functionality includes tests where appropriate.

If Docker is used, verify that the Community environment can still start successfully after your changes.

## 5. Commit Your Changes

Use clear and descriptive commit messages.

Examples:

```text
feat: add project dashboard improvements
```

```text
fix: resolve UI test generation issue
```

```text
docs: improve installation instructions
```

```text
refactor: simplify project configuration
```

## 6. Push Your Branch

Push the branch to your fork:

```bash
git push origin feature/your-feature-name
```

## 7. Create a Pull Request

Create a Pull Request from your branch to the `main` branch of the TuringOne Community repository.

Your Pull Request should clearly explain:

* What was changed
* Why the change was necessary
* How the change was tested
* Any known limitations
* Screenshots for UI changes, when relevant

Please keep Pull Requests focused and reasonably small whenever possible.

## Pull Request Checklist

Before submitting your Pull Request, verify that:

* [ ] My changes are limited to the intended feature or fix.
* [ ] The project builds successfully.
* [ ] I tested the changes locally.
* [ ] Existing tests still pass.
* [ ] I added or updated tests where appropriate.
* [ ] I did not commit secrets, credentials, tokens, or `.env` files.
* [ ] I did not include confidential or customer information.
* [ ] I updated the documentation where necessary.
* [ ] My code follows the existing project structure and conventions.

## Reporting Bugs

Before reporting a bug, please check the existing GitHub Issues to make sure it has not already been reported.

When reporting a bug, include as much relevant information as possible:

* TuringOne Community version
* Operating system
* Docker / Docker Compose version
* Steps to reproduce
* Expected behavior
* Actual behavior
* Relevant logs
* Screenshots, when applicable

Please remove passwords, tokens, API keys, customer data, and other sensitive information from logs and screenshots.

## Feature Requests

Feature requests are welcome.

When proposing a new feature, please explain:

* The problem you are trying to solve
* The expected behavior
* Why the feature would be useful for the Community Edition
* Any technical considerations you have identified

Submitting a feature request does not guarantee that it will be included in the project.

## Security

Please **do not publicly disclose security vulnerabilities through GitHub Issues or Pull Requests**.

If you discover a potential security vulnerability, follow the security reporting instructions provided by the project.

Never include:

* passwords
* access tokens
* API keys
* private keys
* authentication secrets
* customer credentials
* production data

in issues, commits, Pull Requests, screenshots, or logs.

## Community Edition Scope

TuringOne Community is intentionally designed as a lightweight Community Edition.

Some capabilities available in other TuringOne editions may not be available in this repository.

Contributions should respect the scope and architecture of the Community Edition.

Please avoid introducing dependencies on proprietary, private, or enterprise-only components.

## Review Process

All contributions are reviewed before being merged.

Maintainers may:

* Request changes
* Suggest an alternative implementation
* Ask for additional tests
* Request documentation updates
* Decline a contribution if it does not align with the project direction

Approval of a Pull Request is required before it can be merged into `main`.

## License

TuringOne Community is licensed under the GNU Affero General Public License v3.0 (`AGPL-3.0-only`).

By contributing to TuringOne Community, you agree that your contributions will be distributed under the license applicable to this repository.

You keep the copyright on your contributions. There is no contributor license agreement and no copyright assignment.

Please review the repository's [`LICENSE`](LICENSE) file before contributing.

## Thank You

Thank you for helping improve **TuringOne Community**.

Your contributions, feedback, bug reports, and ideas help make the project better for everyone.
