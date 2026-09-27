# openblazer

## Releases

Pushes to `dev` build Windows, Linux, and MSIX artifacts without publishing a release.
Pushes to `main` replace the GitHub `nightly` release with those artifacts. Push a tag
named `vMAJOR.MINOR.PATCH` to publish a versioned GitHub release and submit its MSIX
and release notes to Microsoft Store. The major version must be positive; each
component must be at most 65535. The Store MSIX version uses `MAJOR.MINOR.PATCH.0`.

Before tagging, add a nonempty UTF-8 text file at
`deploy/release-notes/vMAJOR.MINOR.PATCH.en-us.txt` to the commit being tagged. Its
contents become both the GitHub release description and the Store's English (US)
release notes. Push the commit before pushing the tag. Only `main` publishes a nightly
release; a tag triggers production regardless of its source branch.

The production job needs GitHub Actions secrets `STORE_ID`, `SELLER_ID`, `TENANT_ID`,
`CLIENT_ID`, and `CLIENT_SECRET`. The associated Partner Center application must have
permission to submit updates, an existing `en-us` listing, and no pending draft.
Package upload creates a new draft before release notes are applied and the submission
is committed. If a pending draft exists, the job stops rather than replacing it. Review
a failed submission in Partner Center before retrying; an interrupted run may leave a
draft behind. Store certification and publication can take longer than the workflow run.

Run `bash deploy/test-deploy.sh` for the offline deployment checks. A real export
requires Godot 4.6.2, its matching Windows and Linux export templates, `xsltproc`, and
Docker access to `ghcr.io/soerenkoehler-org/docker-msix:main`. The packer image builds
from a mutable upstream SDK revision, so check the image digest before relying on a
production build.
