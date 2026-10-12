# Citable release procedure

Create the submission release from the exact source and results cited by the paper.

1. Confirm the README and CITATION.cff identify the public repository:
   https://github.com/Kabhub/memristor-bist-diagnosis-voting
   Cite this same URL in the manuscript data-availability statement.
2. Run `python scripts/verify_package.py` and confirm docs/RESULT_CHECKS.md against
   the recorded CSVs. If files changed, refresh MANIFEST_SHA256.json before the
   final integrity check; do not replace recorded results with new runs.
3. For the submission release, set `version: "1.0"` and the actual `date-released`
   in CITATION.cff. Commit all release files, create tag `v1.0` at that commit and
   publish a GitHub release from that tag. Do not move the tag after publication.
4. Enable the repository in Zenodo's GitHub integration before publishing the
   release if using that archive route. Check the deposited files and metadata.
5. When Zenodo assigns a DOI, cite the version DOI for the fixed experimental
   artifact. Add the actual DOI to CITATION.cff, the README and the paper; record
   that citation-metadata update in a later commit without moving `v1.0`.

The ZIP is a prepared source/data package. These instructions do not indicate
that a public release or DOI has already been created.

Official guidance:
- https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
- https://help.zenodo.org/docs/github/
