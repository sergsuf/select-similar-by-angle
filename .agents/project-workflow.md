# Select Similar by Angle: project workflow

## Working agreement

- Implement and verify requested changes in the existing project.
- A request to change or fix the script authorizes implementation and relevant
  testing. It does not authorize a commit, a release build, or installation.
- Commit only when the user explicitly asks for a commit. Include the requested
  changes and report the commit hash. A commit request does not authorize a
  release build, push, tag, publication, or installation.
- Build a release only when the user explicitly asks for a release or MZP build.
  In this project, "release" means creating the local `.mzp` in `dist/`.
- A release request does not authorize creating a GitHub Release, uploading
  assets, publishing to a marketplace, pushing commits or tags, or installing
  the package. Perform these actions only when separately requested.
- Do not build an MZP after each feature change or fix. Several changes can
  accumulate before the user requests a release.
- Before a requested release build, check the current source, version,
  changelog, package identity and file paths. Build from the current requested
  project state and report its version and output path. Do not automatically
  commit release preparation changes.
- Treat versioned sibling directories as historical copies. Continue work in
  this canonical `select-similar-by-angle` Git project; do not create a new
  project directory for every update.

## Project layout

- `select_similar_coplanar.ms`: runtime and UI for polygon, Loop and Ring
  selection on the active Editable Poly or Edit Poly cage.
- `lib/AgAngleSliderV3.dll`: packaged slider assembly, loaded relative to the
  runtime file. Rebuild only when its C# implementation changes.
- `maxpkg-packager.ini`: package settings, version and authoring paths.
- `maxpkg-changelog.ini`: release history.
- `maxpkg-packager.ms`, `_install.ms`, `_uninstall.ms`: official MaxPkg tools
  and hooks. Preserve them unless the task explicitly requires a change.
- `source/`: slider sources, behavioral checks and verification records.
- `dist/`: local MZP artifacts.
- `marketplace/`: listing copy and artwork.
- `AGENTS.md` and `.agents/`: persistent project instructions.

The current `.gitignore` excludes `source/`, `dist/` and `marketplace/`.
Do not force-add these paths or change that policy without a user request.
Preserve package GUID `aab0c84a-1eb7-41e1-afeb-0667942bdc08` for updates.

## Implementation and verification

- Keep source comments, UI, documentation and release notes in English.
  Communicate with the user in Ukrainian.
- Use Max Ultra MCP for live 3ds Max inspection and behavioral verification.
  List instances and select the intended instance before operating.
- Mutate Max serially. Preserve the user's scene, geometry, selection and
  active stack; clean up temporary test objects.
- Work on the active Editable Poly base or Edit Poly modifier, including
  modifiers above it. Do not collapse the stack to implement selection.
- After relevant changes, use the behavioral scripts in `source/` when
  available: `test-selection.ms` for Polygon/Loop and `test-ring.ms` for Ring.
  Load the source runtime directly for development; tests do not require a
  release build or installation.
- Report the Max version tested and any material verification limits.

## Requested local release

1. Verify the intended version, changelog and current project file paths.
2. Use Max Ultra MCP to run this project's `maxpkg-packager.ms` in 3ds Max.
3. Use `MaxPkgPackerApi.invoke "package.validate"` and
   `MaxPkgPackerApi.invoke "package.build"`.
4. Verify the resulting MZP manifest, runtime entry and required DLL/hooks.
5. Return a link to the local artifact in `dist/`.

Do not interpret this workflow as standing authorization to build, install,
commit or publish. Follow the user's explicit instruction for each action.
