# Releases

The overall repository and pipeline architecture is documented in
`ARCHITECTURE.md`.

The API, admin application, and customer application use independent Semantic
Versioning. The root repository records the exact combination deployed to
production in `release.env` and gives that combination a CalVer deployment ID.

## Versioning rules

- Increment `MAJOR` for incompatible API or behavior changes.
- Increment `MINOR` for backward-compatible features.
- Increment `PATCH` for backward-compatible fixes.
- Change only the services included in a release. A customer-application-only
  release leaves the API and admin versions and commits unchanged.
- Every component version is immutable. A Docker tag such as
  `monino-tools-user:1.2.0` must always refer to the commit recorded in its OCI
  image label.
- A successful production build also creates a full-SHA alias such as
  `monino-tools-user:<40-character-commit>` for exact image identification.
- Use Conventional Commit prefixes (`feat:`, `fix:`, `refactor:`, `docs:`,
  `chore:`, `ci:`, `ops:`) so Release Please can calculate and document the next
  version.

Each component keeps its own `CHANGELOG.md`. The root `CHANGELOG.md` describes
deployment and infrastructure changes.

## Preparing a component release

For every changed component:

1. Use Conventional Commit messages for all changes.
2. Push the changes and wait for the component CI to pass.
3. Review the release PR created or updated by Release Please. It changes
   `package.json`, `package-lock.json`, `.release-please-manifest.json`, and
   `CHANGELOG.md`.
4. Approve the release PR workflow when GitHub requires maintainer approval and
   wait for all checks to pass.
5. Merge the release PR. Release Please creates the matching `v<version>` tag
   and GitHub Release.

Do not manually edit the version or create a tag for a normal component release.
Do not release unchanged components.

## Preparing the deployment manifest

Update `release.env` with:

- a new `RELEASE_VERSION` in `YYYY.MM.DD.N` format;
- the SemVer and full commit SHA for each component;
- the root `INFRA_VERSION` from `VERSION`.

Run:

```sh
./validate-release.sh
docker compose --env-file release.env config --quiet
```

Commit the root repository after all component commits are available remotely,
then tag the root commit as `v<INFRA_VERSION>`. Bump `INFRA_VERSION` whenever a
new immutable root release tag is needed, including a deployment-manifest-only
change.

## Deploying

Run the `Production operations` workflow in the customer application repository
with operation `verify` and the exact root tag in `release_ref`. After isolated
verification succeeds, run it again with operation `deploy` and the same tag.

`deploy.sh` compares the currently running image tag with `release.env`. It
builds and recreates only changed services. It runs database migrations and the
image cleanup task only when the API changes. Every deployment creates a backup
that includes its release manifest.

For example, a customer-application-only release changes `USER_VERSION` and
`USER_COMMIT`; the deployed API and admin containers remain running.

## Rolling back

The deploy script stores the previously running image tags in
`.previous-release.env`. Run the production workflow with operation `rollback`
to restore those images and run the smoke test. Rollback intentionally leaves
database migrations in place, so API migrations must remain compatible with the
previous application version.
