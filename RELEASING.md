# Releasing

## Versioning

Jevons follows [Semantic Versioning](https://semver.org/). During the `v0.x` series:

- **MINOR** bumps may include breaking changes (documented in CHANGELOG)
- **PATCH** bumps are backward-compatible fixes only
- The `v0.x` series makes no stability guarantees — expect iteration

Once `v1.0.0` is reached, standard SemVer rules apply.

## Release Checklist

1. Update `CHANGELOG.md` — move Unreleased items under new version header
2. Update version constant in `cmd/jevons/main.go`
3. Commit: `chore(release): prepare vX.Y.Z`
4. Tag: `git tag vX.Y.Z`
5. Push: `git push origin main --tags`
6. GoReleaser builds and publishes artifacts automatically via CI
7. Verify artifacts on GitHub Releases page
8. Verify checksums file is published
9. Run smoke tests against released binary:
   - `jevons sync`
   - `jevons web` (verify dashboard loads)
   - `jevons status`
   - `jevons doctor`
10. Update Homebrew tap formula (if applicable)

## Rollback

If a release has a critical defect:

1. Identify the issue and severity
2. If data corruption risk: immediately yank the release (`gh release delete vX.Y.Z`)
3. Fix the issue on `main`
4. Cut a patch release (`vX.Y.Z+1`) following the checklist above
5. Document the incident in CHANGELOG under the patch version

## Build Targets

| OS | Arch |
|----|------|
| darwin | amd64 |
| darwin | arm64 |
| linux | amd64 |
| linux | arm64 |
