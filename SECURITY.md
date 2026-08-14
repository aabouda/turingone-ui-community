# TuringOne Community — Security Policy

Security is an important part of **TuringOne Community**.

This document describes the main security principles of the Community Edition, the responsibilities associated with self-hosted deployment, and how security vulnerabilities should be reported.

> **TuringOne Community is a self-hosted application.**  
> The organization operating the platform is responsible for securing the host machine, Docker environment, network exposure, backups, and infrastructure credentials.

---

## 1. Reporting a Security Vulnerability

Please **do not report security vulnerabilities through public GitHub Issues, Discussions, or Pull Requests**.

If you believe you have discovered a security vulnerability in TuringOne Community, please contact the TuringOne team privately.

When reporting a vulnerability, please include:

- The affected TuringOne Community version
- A clear description of the vulnerability
- Steps to reproduce the issue
- The potential security impact
- Relevant logs or screenshots, with sensitive information removed
- Any suggested mitigation, if available

Please do not include:

- Passwords
- API keys
- Access tokens
- Refresh tokens
- Private keys
- Customer data
- Production credentials
- Confidential project information

---

## 2. Responsible Disclosure

We ask security researchers and users to follow responsible disclosure practices.

Please allow the TuringOne team reasonable time to:

1. Confirm the vulnerability
2. Assess its impact
3. Develop and test a fix
4. Prepare a security update
5. Notify affected users when necessary

Please avoid publicly disclosing vulnerability details before a fix or mitigation is available.

---

## 3. Supported Versions

Security updates are primarily provided for the latest available version of TuringOne Community.

| Version | Supported |
|---|---|
| Latest release | ✅ Yes |
| Older releases | ⚠️ Best effort |
| Development snapshots | ❌ No guarantee |

Users are strongly encouraged to keep their TuringOne Community installation up to date.

---

## 4. Security Architecture

TuringOne Community uses a containerized architecture designed to reduce unnecessary exposure between services.

The deployment may include services such as:

- TuringOne Frontend
- TuringOne Backend
- Keycloak
- PostgreSQL
- MinIO
- RabbitMQ
- Redis

Infrastructure services such as PostgreSQL, MinIO, RabbitMQ, and Redis should remain on private Docker networks and should **not expose ports directly to external networks unless explicitly required**.

Only services that require user access should be exposed.

---

## 5. Database and Storage Protection

### Network Isolation

Database and infrastructure services are configured to operate on internal Docker networks whenever possible.

They should not publish database or internal service ports directly to the host or the Internet.

This significantly reduces the network attack surface.

However, Docker network isolation must not be considered protection against an administrator who controls the host machine.

### Generated Credentials

TuringOne Community installation scripts generate strong credentials instead of relying on fixed default passwords.

Secrets must never be:

- Committed to Git
- Included in Docker images
- Stored in source code
- Included in screenshots
- Published in documentation
- Shared through public support channels

Each installation should use its own credentials.

Credentials from one TuringOne installation must never be reused for another environment.

### PostgreSQL Least Privilege

TuringOne follows the principle of least privilege for database access.

Application services should use dedicated PostgreSQL accounts without unnecessary administrative privileges.

The PostgreSQL superuser should only be used for operations that explicitly require administrative access, such as initial database provisioning.

Application services should never operate permanently using a PostgreSQL superuser account.

---

## 6. Application-Level Encryption

Sensitive third-party credentials stored by TuringOne may include configuration for services such as:

- Jira
- Xray
- Azure DevOps
- Git providers
- External authentication systems
- API integrations

Sensitive credentials should be encrypted before being persisted.

TuringOne Community uses application-level encryption mechanisms to protect sensitive configuration data.

Encryption keys must be stored separately from the encrypted database content whenever possible.

A stolen database dump alone should not be sufficient to recover protected credentials.

---

## 7. Master Key Protection

The TuringOne master encryption key is a critical security asset.

It must:

- Never be committed to Git
- Never be included in Docker images
- Never be published in documentation
- Be different for each installation
- Be backed up securely
- Be stored separately from database backups whenever possible

Losing the master key may make encrypted application credentials unrecoverable.

Compromising the master key may compromise encrypted application secrets.

Treat it accordingly.

---

## 8. Docker Host Security

TuringOne Community is self-hosted, which introduces an important security boundary.

> An administrator who fully controls the Docker host can potentially access containers, environment variables, volumes, process memory, configuration files, and application data.

This is an inherent property of self-hosted software and container environments.

TuringOne Community is primarily designed to protect against:

- Unauthorized application users
- Network-based attackers
- Accidental service exposure
- Unprivileged access between services

It cannot technically prevent a fully privileged host administrator from inspecting the environment.

Therefore:

- Restrict Docker access to trusted administrators
- Restrict SSH/RDP access to the host
- Keep the operating system patched
- Use host-based firewall rules
- Protect Docker daemon access
- Avoid exposing the Docker socket
- Never mount `/var/run/docker.sock` into application containers unless absolutely necessary

---

## 9. Container Hardening

Where supported by the application architecture, TuringOne containers should follow these principles:

- Run applications as non-root users
- Minimize writable filesystem locations
- Drop unnecessary Linux capabilities
- Avoid privileged containers
- Avoid host networking
- Avoid mounting sensitive host directories
- Use minimal runtime images
- Remove development tools from production images
- Separate build and runtime stages
- Limit exposed ports
- Configure CPU and memory limits when appropriate

These controls reduce the impact of a potential container compromise.

---

## 10. HTTPS and Network Exposure

TuringOne Community may use HTTP for local development environments.

For any deployment accessible beyond `localhost`, **HTTPS is strongly recommended and should be considered mandatory for production or shared environments**.

A TLS reverse proxy can be placed in front of TuringOne services, for example:

- Caddy
- Traefik
- Nginx
- An equivalent enterprise reverse proxy

The reverse proxy should terminate TLS and forward traffic only to the required TuringOne services.

Never expose the following directly to the public Internet unless explicitly required and properly secured:

- PostgreSQL
- Redis
- RabbitMQ
- MinIO administrative interfaces
- Internal backend services

---

## 11. Authentication

Authentication is provided through **Keycloak** using OpenID Connect.

The authentication architecture supports modern authentication mechanisms such as:

- OpenID Connect
- Authorization Code Flow
- PKCE
- Centralized identity management
- Account security policies
- Brute-force protection where configured

Application passwords are not stored directly by TuringOne when authentication is delegated to Keycloak.

### Keycloak Administration

The Keycloak administrative account is a technical infrastructure account.

It should:

- Be restricted to trusted administrators
- Never be distributed to normal application users
- Use a strong unique password
- Be protected from unnecessary network exposure

Application administrators should use application-level roles whenever possible rather than Keycloak infrastructure administration accounts.

If remote Keycloak administration is not required, access to administrative endpoints should be restricted through the reverse proxy, firewall, VPN, or equivalent infrastructure controls.

---

## 12. Tenant Isolation

TuringOne Community is primarily intended for a controlled self-hosted environment.

Administrators should avoid creating additional authentication realms, tenants, or environments unless they understand the associated authorization and isolation implications.

Production and testing authentication configurations should preferably remain separated.

Do not reuse production credentials or identity infrastructure for development environments unless explicitly designed for that purpose.

---

## 13. Protection of TuringOne Source Code

TuringOne Community may be distributed using pre-built container images rather than source code.

Production images should contain only the files required at runtime.

Development resources should be excluded whenever possible, including:

- Internal development scripts
- Deployment tooling not required at runtime
- Temporary files
- Database dumps
- Internal documentation
- Build tools
- Development credentials
- Test credentials

Frontend production builds should also avoid publishing source maps unless they are specifically required.

### Important Limitation

Container images must **not** be considered a secure mechanism for keeping code completely secret.

A user with sufficient control over the Docker host may inspect or extract application files from a container image.

Compiled or packaged code may make reverse engineering more difficult, but it does not make reverse engineering impossible.

Therefore:

> Any algorithm, prompt, model configuration, credential, key, or intellectual property that must remain strictly confidential should not be distributed to an environment controlled by an untrusted third party.

Sensitive or highly differentiated capabilities may instead be provided through services controlled by TuringOne.

---

## 14. Secrets Management

Environment variables may be used by the Community Edition for deployment simplicity.

Operators should understand that users with administrative access to the Docker host may be able to inspect container configuration.

For environments requiring stronger protection, consider using a dedicated secrets-management solution such as:

- Docker Secrets
- HashiCorp Vault
- SOPS
- Cloud-native secrets managers
- Enterprise credential vaults

Never store real secrets inside `.env.example`.

The repository should contain placeholders only.

Example:

```env
DATABASE_PASSWORD=
TURINGONE_MASTER_KEY=
EXTERNAL_API_TOKEN=
```

Never use:

```env
DATABASE_PASSWORD=my-real-production-password
```

---

## 15. Backup Security

Backups may contain highly sensitive information.

Depending on the deployment, backups may include:

- PostgreSQL data
- Uploaded documents
- MinIO objects
- Project configuration
- Application credentials
- Encryption metadata

Backups must therefore receive security protection equivalent to the production environment.

Recommended controls include:

- Encryption at rest
- Restricted administrator access
- Secure off-site backup storage
- Retention policies
- Periodic restore testing
- Separation between encryption keys and encrypted backups

The encryption master key must also be backed up securely.

Without the appropriate encryption keys, some encrypted application data may not be recoverable after restoration.

---

## 16. Logging

Application logs must not intentionally contain sensitive authentication information.

Do not log:

- Passwords
- Private keys
- Access tokens
- Refresh tokens
- Authorization headers
- Database passwords
- Encryption keys

Administrators should also review application and reverse-proxy logs before sharing them publicly.

Logs included in GitHub Issues or support requests must have sensitive information removed.

---

## 17. Docker Images

For production-style deployment, TuringOne Community should preferably use versioned container images.

Avoid relying permanently on:

```text
latest
```

Prefer immutable image versions or digests whenever practical.

Images should be:

- Built through a controlled build process
- Scanned for known vulnerabilities
- Updated regularly
- Distributed through a trusted registry
- Signed or verified when image-signing infrastructure is available

Never include secrets in Docker build arguments, Docker layers, or image history.

---

## 18. Dependency Security

TuringOne Community depends on third-party libraries and container images.

Security therefore also depends on keeping dependencies current.

Maintainers should regularly review:

- Python dependencies
- Node.js dependencies
- Base Docker images
- Keycloak versions
- PostgreSQL versions
- Redis versions
- RabbitMQ versions
- MinIO versions
- Frontend dependencies

Automated dependency and vulnerability scanning is recommended.

---

## 19. Community Edition Security Model

TuringOne Community is intended to provide a practical self-hosted experience while maintaining reasonable security defaults.

The Community Edition should not be considered equivalent to a fully managed hardened enterprise deployment.

Organizations with stronger requirements involving:

- Advanced identity management
- Corporate SSO
- Fine-grained network segmentation
- Centralized secrets management
- Advanced auditing
- Regulatory requirements
- Enterprise monitoring
- High-availability infrastructure
- Advanced tenant isolation

should perform an additional security assessment before deployment.

---

## 20. Deployment Security Checklist

Before making a TuringOne Community installation available to users, verify the following:

- [ ] A unique `.env` has been generated for this installation.
- [ ] No default passwords are being used.
- [ ] No secrets are committed to Git.
- [ ] The master encryption key has been backed up securely.
- [ ] The master encryption key is stored separately from database backups.
- [ ] Internal database and infrastructure ports are not publicly exposed.
- [ ] HTTPS is enabled when the application is accessible beyond localhost.
- [ ] Docker host access is restricted to trusted administrators.
- [ ] Keycloak administrator access is restricted.
- [ ] Application users do not receive infrastructure administrator credentials.
- [ ] Production container images do not contain development credentials.
- [ ] Production container images do not contain unnecessary source or development files.
- [ ] Database backups are configured.
- [ ] Object-storage backups are configured when applicable.
- [ ] Backup restoration has been tested.
- [ ] Sensitive logs are protected.
- [ ] Container images come from a trusted registry.
- [ ] The `LICENSE` file (AGPL-3.0-only) is included with the distribution.
- [ ] The operating system and Docker environment are up to date.

---

## 21. Security Is a Shared Responsibility

TuringOne provides application-level security controls, but the security of a self-hosted installation also depends on the operator.

The organization deploying TuringOne Community is responsible for securing:

- The host operating system
- Docker
- Network access
- Firewalls
- TLS certificates
- DNS
- Authentication configuration
- Backups
- Administrator accounts
- Infrastructure credentials

A secure application cannot compensate for a compromised or improperly configured host environment.

---

## Security Contact

Security vulnerabilities should be reported privately to the TuringOne team.

**Do not publish vulnerability details in GitHub Issues or Discussions.**

Security contact:

```text
contact@getturingone.com
```

Replace this address with the official TuringOne security email before publication.

---

## License

TuringOne Community is distributed under the GNU Affero General Public License v3.0 (`AGPL-3.0-only`).

Please refer to the [`LICENSE`](LICENSE) file for the applicable terms and conditions.

---

Copyright © 2026 TuringOne — licensed under AGPL-3.0-only.
