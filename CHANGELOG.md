# Changelog

All notable changes of `dlc-patient-db` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/). A release is tagged `v<version>` once it is merged into `main`.

## [Unreleased]

## [3.0.0] - 2026-11-14

The changelog starts at this release.

### Added

- Add patient identity schema and constraints.
- Add emergency contacts schema and constraints.
- Add append-only audit schema and verification.
- Add scoped idempotency records and verification.
- Add transactional outbox storage and verification.
- Add durable inbox storage and deduplication.
- Add least-privilege runtime permissions.
- Add environment bootstrap and scoped migrator.
- Persist durable deactivation operations.
- Add pagination and substring search indexes.
- Add isolated synthetic development seeds.
- Add reader, writer and app domain roles.
- Enforce atomic deactivation at commit.
- Store the closed deactivation reason code.
- Separate migration settings per environment.
- Remove the synthetic seed snapshots in dev and qa.

### Fixed

- Guard every rollback with history validation.
- Make the synthetic seed an upsert.
