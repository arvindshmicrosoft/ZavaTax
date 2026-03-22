# Contributing to Zava Tax

Thank you for your interest in contributing to this project! This document provides guidelines and information for contributors.

## Project Context

> **Important:** This is an individual open-source project maintained under the [`arvindshmicrosoft`](https://github.com/arvindshmicrosoft) GitHub organization. While the maintainer is a Microsoft employee, this project is **not** an official Microsoft product, service, or endorsed offering. Contributions are managed by the individual maintainer, not by Microsoft.

## How to Contribute

### Reporting Issues

- Use the GitHub Issues tab to report bugs or suggest enhancements.
- Search existing issues before creating a new one to avoid duplicates.
- Provide as much detail as possible: steps to reproduce, expected behavior, actual behavior, and environment details (OS, SQL Server version, Node.js version, etc.).

### Suggesting Features

- Open a GitHub Issue with the **enhancement** label.
- Describe the use case and why the feature would be valuable for the demo.

### Submitting Pull Requests

1. **Fork** the repository and create your branch from `main`.
2. **Make your changes** in a focused, well-scoped branch.
3. **Test** your changes locally to ensure nothing is broken.
4. **Follow existing code style** and conventions used in the project.
5. **Write clear commit messages** that describe what changed and why.
6. **Open a pull request** against `main` with a clear description of the changes.

### Pull Request Guidelines

- Keep PRs small and focused on a single change when possible.
- Reference any related issues in the PR description (e.g., "Fixes #42").
- Ensure your code does not introduce security vulnerabilities — see [SECURITY.md](SECURITY.md).
- Be patient — this is maintained by an individual in their personal capacity, so review times may vary.

## Development Setup

See the [README.md](README.md) for prerequisites and setup instructions, including:

- Node.js, Python, .NET SDK, and SQL Server requirements
- Data API Builder installation
- Database setup and data loading
- Running the web application locally

## Code Style

- **TypeScript/React** (webapp): Follow the existing ESLint configuration in [eslint.config.js](webapp/eslint.config.js).
- **Python** (data-prep, load-simulator): Follow PEP 8 conventions.
- **SQL** (database): Use the formatting conventions in the existing SQL scripts.

## Legal

### Contributor License

By submitting a pull request, you confirm that:

1. You have the right to submit the contribution under the project's [MIT License](LICENSE).
2. Your contribution does not include code copied from sources incompatible with the MIT License.
3. You understand this is an individual project and your contribution is not being made to or on behalf of Microsoft.

### License

This project is licensed under the [MIT License](LICENSE). By contributing, you agree that your contributions will be licensed under the same terms.

## Code of Conduct

This project has adopted a Code of Conduct based on the Contributor Covenant. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for details.

## Questions?

If you have questions about contributing, feel free to open a GitHub Issue for discussion.
