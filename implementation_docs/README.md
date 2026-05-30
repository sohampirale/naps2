# Implementation Docs: Cloud Upload for NAPS2

This directory contains all documentation for implementing a cloud upload feature in the NAPS2 open-source scanning project.

## Documents

| Document | Description |
|----------|-------------|
| [01_feasibility_assessment.md](01_feasibility_assessment.md) | Is it possible? What exists vs. what needs to be built |
| [02_architecture_overview.md](02_architecture_overview.md) | High-level architecture of the feature |
| [03_integration_points.md](03_integration_points.md) | Exact files and line numbers to modify |
| [04_implementation_plan.md](04_implementation_plan.md) | Phased plan for building the feature |
| [05_reference_code_patterns.md](05_reference_code_patterns.md) | Code examples from NAPS2 to follow |
| [06_provider_details.md](06_provider_details.md) | Technical details for each cloud provider |
| [07_settings_and_ui.md](07_settings_and_ui.md) | UI design and settings storage |
| [08_security_considerations.md](08_security_considerations.md) | Security best practices |
| [09_getting_started.md](09_getting_started.md) | How to begin implementation |
| [10_web_frontend_and_remote_triggering.md](10_web_frontend_and_remote_triggering.md) | Web frontend + cloud-triggered scanning system |

## Two Scopes

### Scope 1: Cloud Upload Only (Simpler)
Add automatic upload to cloud after scanning. NAPS2 runs normally (GUI or CLI), saves PDF locally, then uploads it to a cloud provider.

- **Effort:** ~6 weeks full-time
- **AI-assisted effort:** ~1-2 weeks
- [Start here](09_getting_started.md)

### Scope 2: Web Frontend + Remote Scan Triggering (Full Platform)
Build a system where a web frontend communicates with a cloud service, which sends scan instructions to NAPS2 (specific scanner, folder, settings). NAPS2 runs as a background service with an HTTP API.

- **Effort:** ~8-12 weeks full-time
- **AI-assisted effort:** ~3-6 weeks
- [See full architecture](10_web_frontend_and_remote_triggering.md)

## Key Technologies That Make This Possible

| Need | What NAPS2 Already Has |
|------|----------------------|
| HTTP client | `HttpClient`, `WebClient`, `WebClientExtensions` |
| OAuth2 | `OauthProvider` base class (Gmail, Outlook) |
| Plugin pattern | `IEmailProvider` / `IEmailProviderFactory` |
| Background ops | `IOperation` with progress/cancellation |
| PDF to stream | `PdfExporter.Export(Stream)` |
| DI wiring | Autofac modules |
| Credential storage | `CredentialManager` (OS keychain) |
| Embedded HTTP server | **EmbedIO** (used by `EsclServer` for ESCL protocol) |
| Programmatic scan API | `ScanController` in `NAPS2.Sdk` |
| Dynamic folder output | `AutoSaveSettings.FilePath` with placeholders |
| Local IPC | gRPC + named pipes (`WorkerService`, `ProcessCoordinatorService`)
