# openblazer

## Releases

Every branch push builds Windows, Linux, and MSIX artifacts and replaces that
branch's GitHub nightly release. The release tag is `nightly-<branch>`, with each
branch character other than an ASCII letter, digit, or hyphen replaced by `-`.
Branches that normalize to the same identifier stop before publication. Nightly
titles use the next patch version and the suffix `-nightly-<branch>`. If no valid
version tag exists, the nightly title starts at `v1.0.0-nightly-<branch>`. Repeated
nightlies use the same version until a new reference tag is pushed. The former shared
`nightly` release is no longer updated.

Push a tag named `vMAJOR.MINOR.PATCH` with an optional nonempty `-comment` to publish
a production release and submit its MSIX and release notes to Microsoft Store. The
comment is ignored when determining the version. Components must use canonical
decimal notation (no leading zeroes except `0`). Branch builds select the highest
numeric version among matching Git tags, then increment its patch. If multiple tags
have the selected version after comments are ignored, the pipeline stops. Production
release identifiers retain the pushed tag, while release titles use
`vMAJOR.MINOR.PATCH` without a comment.

Before tagging, add a nonempty UTF-8 text file at
`deploy/release-notes/vMAJOR.MINOR.PATCH.en-us.txt` to the commit being tagged. Its
contents become both the GitHub release description and the Store's English (US)
release notes. Push the commit before pushing the tag. The major version must be
positive; each MSIX component must be at most 65535. The Store MSIX version uses
`MAJOR.MINOR.PATCH.0`. If the selected reference is outside those limits or its patch
cannot be incremented within the limit, the pipeline stops. The workflow also stops
if tag changes between packaging and publication would produce a different MSIX
version; rerun the workflow after the tag set is stable.

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
