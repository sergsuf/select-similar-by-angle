Select Similar by Angle - MaxPkg 1.2.1

Activate an Editable Poly base or Edit Poly modifier in the Modify panel.
Modifiers above the active cage are supported and preserved.
Enter Polygon (4) or Edge (2) mode; other levels remain inactive.

Polygon mode
Existing All / Row / Column, connected, same-element and recursive filters.
Topology and normals are read at the active cage, including Edit Poly on
non-poly primitives. Evaluated geometry above the cage is not used.

Edge mode
Select one or more seed edges, then adjust Loop Turn Angle or a preset.
Auto-expand on viewport click also supports edges.
Loops follow connected edges through vertices in both directions.
Interior continuation requires valence four and one edge sharing no face
with the incoming edge. Ambiguous poles stop traversal.
On open boundaries, exactly two boundary edges must meet at a vertex.
Turn angle along traversal: straight = 0, right turn = 90 degrees.
Standard mode compares with the seed traversal direction.
Recursive compares each segment with its preceding segment.
Zero keeps only the seeds. For a complete curved loop, enable Recursive
and raise the threshold above the largest segment turn.
All / Row / Column, Connected and Same element are disabled in Edge mode.
Replace / Add / Subtract and session presets apply to both component types.
Switch Edge Traversal between Loop and Ring without changing the seeds.
Ring crosses each quad to its opposite edge, in both directions.
Ring Edge Angle compares the directions of opposite edges, ignoring endpoint
numbering: parallel = 0 degrees, perpendicular = 90 degrees.
Recursive compares consecutive edges; standard compares with the seed edge.
Zero keeps the seeds, as in Loop. Ring stops at non-quads, boundaries,
degenerate edges and closed cycles. Multiple seed edges are supported.
Angles use active-cage object coordinates.

Update and build
dist contains the compiled MZP for 1.2.1.
The original 1.0.1 and 1.1.0 projects are preserved in sibling folders.
Package GUID is unchanged so MaxPkg updates the existing installation.
Run maxpkg-packager.ms in Max and click Build MZP to rebuild.
Update absolute paths in maxpkg-packager.ini if moving the project.
The runtime loads lib/AgAngleSliderV3.dll relative to its own file.
Official packager and lifecycle hooks are unchanged.
The runtime does not register additional macros.

Validation
40 behavioral checks passed via Max Ultra MCP in 3ds Max 2025.3.
Load the runtime then run source/test-selection.ms and source/test-ring.ms.
The tests clean up their temporary nodes and restore the user's selection,
active stack, sub-object level and tool settings.
Coverage: base below TurboSmooth; polygon flood/row/column; straight loops;
multiple seeds; zero angle/re-expansion; boundary corners and closure;
unsupported modifier/vertex rejection; Edit Poly on a primitive;
modifier normals/flood/row/loop; viewport callback; Add; recursive curved
loop; absolute-angle stopping; threshold below the next turn.
Additional package checks are recorded in source/verification-1.2.0.txt.
Only 2025.3 was tested for this update. The inherited minimum version 2012
is unverified. UI screenshot verification was unavailable through this
bridge; rollout state and actual selection results were checked directly.

Project language
All comments, interface text, docs and marketplace copy must be English.
Developer: Sergij Vari. License: Free.

Release numbering: use major.minor versions (2.2 through 2.9, then 3.0). MaxPkg requires major.minor.patch, so package metadata uses a fixed .0 patch (for example, 2.2.0).
