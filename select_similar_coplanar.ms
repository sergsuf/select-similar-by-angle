-- =============================================================================
-- Tool: Select Similar by Angle 1.1.0 (Polygon / Edge Loop)
-- File: select_similar_coplanar.ms (MaxPkg package runtime)
-- Category: Antigravity Tools
-- Description: Ultra-fast face selection by angle with surface flood-fill,
--              Direction modes: All (Flood) / Row (Horizontal) / Column (Vertical),
--              Reliable auto-expand on viewport click (no missed clicks),
--              Active Editable Poly / Edit Poly at Polygon or Edge level,
--              >50k heavy mesh 1s throttle protection, zero idle overhead,
--              and in-memory presets.
-- =============================================================================

global rol_SelectCoplanarTool
global rol_SelectCoplanar_SessionPresets
global rol_SelectCoplanar_NodeCallback
global rol_SelectCoplanar_IsUndoing = false

-- Factory defaults
global rol_SelectCoplanar_DefaultPresets = #(5.0, 10.0, 15.0, 20.0, 30.0, 45.0)

if rol_SelectCoplanar_SessionPresets == undefined do
    rol_SelectCoplanar_SessionPresets = copy rol_SelectCoplanar_DefaultPresets #nomap

-- Load the packaged slider; runtime CodeDom compilation is unsupported in Max 2027.
if ((dotnet.getType "AgAngleSliderV3") == undefined) do (
    local scriptFolderPath = getFilenamePath (getThisScriptFileName())
    local sliderAssemblyPath = scriptFolderPath + "lib\\AgAngleSliderV3.dll"
    if (not (doesFileExist sliderAssemblyPath)) do throw ("Slider assembly not found: " + sliderAssemblyPath)
    dotNet.loadAssembly sliderAssemblyPath
    if ((dotnet.getType "AgAngleSliderV3") == undefined) do throw "Could not load the packaged angle slider."
)
-- Clean up any existing instance or callback
try (destroyDialog rol_SelectCoplanarTool) catch()
try (rol_SelectCoplanar_NodeCallback = undefined) catch()
try (callbacks.removeScripts id:#AgSelectCoplanarUndo) catch()
rol_SelectCoplanar_IsUndoing = false

rollout rol_SelectCoplanarTool "Select Similar by Angle 1.1.0" width:270 height:345
(
    -- UI Configuration: Adjust margins and gaps here
    local btnSideMargin = 12    -- Distance in px from left/right edges of the dialog
    local btnGap = 4            -- Gap in px between adjacent preset buttons
    local btn_width = 38
    local btn_height = 22
    -- 1. Status Display
    label lbl_target "Target: None" align:#left offset:[0,2]
    label lbl_status "Select faces or edges in viewport" align:#left offset:[0,-3]

    -- 2. Angle Controls & 6 Presets
    label lbl_angle "Angle Threshold" align:#left across:2 offset:[0,3]
    spinner spn_angle "" range:[0.0, 180.0, 15.0] type:#float scale:0.01 fieldwidth:55 align:#right offset:[0,2]
    dotNetControl sld_angle "AgAngleSliderV3" width:246 height:28 offset:[0,-1]

    dotNetControl btn_p1 "System.Windows.Forms.Button" width:btn_width height:btn_height across:6 offset:[0,-2]
    dotNetControl btn_p2 "System.Windows.Forms.Button" width:btn_width height:btn_height offset:[0,-2]
    dotNetControl btn_p3 "System.Windows.Forms.Button" width:btn_width height:btn_height offset:[0,-2]
    dotNetControl btn_p4 "System.Windows.Forms.Button" width:btn_width height:btn_height offset:[0,-2]
    dotNetControl btn_p5 "System.Windows.Forms.Button" width:btn_width height:btn_height offset:[0,-2]
    dotNetControl btn_p6 "System.Windows.Forms.Button" width:btn_width height:btn_height offset:[0,-2]

    -- 3. Direction Mode: All / Row / Column
    group "Direction"
    (
        radiobuttons rad_dir labels:#("All", "Row", "Column") default:1 columns:3 offset:[0,-2]
    )

    -- 4. Filter Options
    group "Filters"
    (
        checkbox chk_autoExpand "Auto-expand on viewport click" checked:true tooltip:"Automatically grow selection by the current angle whenever you click or select faces or edges in the viewport"
        checkbox chk_connected "Connected only (Grow)" checked:true tooltip:"Constrain selection to contiguous surfaces sharing edges with the reference face"
        checkbox chk_recursive "Recursive / Step-by-step (Smooth)" checked:false tooltip:"When checked, tests angle between adjacent neighbor faces (smooth surface traversal across curves). When unchecked, tests absolute angle against the clicked reference face."
        checkbox chk_sameElement "Same element only" checked:true tooltip:"Constrain selection to the element of the reference face"
        checkbox chk_throttle50k "Throttle heavy mesh (>50k)" checked:true tooltip:"Limit update rate to 1 second when mesh has more than 50k faces to prevent lag. Uncheck for unrestricted real-time."
    )

    -- 5. Selection Mode
    group "Selection Mode"
    (
        radiobuttons rad_mode labels:#("Replace", "Add", "Subtract") default:1 columns:3 offset:[0,-2]
    )

    -- Internal State
    local currentObj = undefined
    local isEditPolyMod = false
    local activeMod = undefined
    local activeBase = undefined
    local contextKey = undefined
    local isEdgeMode = false
    local cachedNormals = #()
    local numFaces = 0
    local refFaceIndices = #{}
    local refNormals = #()
    local refElementFaces = #{}
    local lastScriptResultFaces = #{}
    local seedList = #()
    local expandedList = #()

    -- In-memory session presets & default values
    local presetValues = rol_SelectCoplanar_SessionPresets
    local defaultPresetValues = rol_SelectCoplanar_DefaultPresets
    local toolTipObj = undefined

    -- Color & UI definitions for preset buttons
    local colActiveBg = (dotnetClass "System.Drawing.Color").FromArgb 30 136 229
    local colNormalBg = (dotnetClass "System.Drawing.Color").FromArgb 58 58 58
    local colNormalFg = (dotnetClass "System.Drawing.Color").FromArgb 225 225 225
    local colActiveFg = (dotnetClass "System.Drawing.Color").White
    local mouseButtonsClass = (dotnetClass "System.Windows.Forms.MouseButtons")

    fn formatAngleCaption val =
    (
        local r2 = ((floor (val * 100.0 + 0.5)) / 100.0)
        if (r2 == floor r2) then
            ((r2 as integer) as string) + "°"
        else
            (formattedPrint (r2 as float) format:".2f") + "°"
    )

    fn updatePresetButtonsUI isDragging:false =
    (
        local btns = #(btn_p1, btn_p2, btn_p3, btn_p4, btn_p5, btn_p6)
        local curA = spn_angle.value

        -- When dragging, only update background highlight to maintain high FPS
        for i = 1 to 6 do
        (
            local v = presetValues[i]
            local btn = btns[i]
            local isMatch = (abs (curA - v) < 0.05)

            if isMatch then
            (
                if btn.BackColor != colActiveBg do
                (
                    btn.BackColor = colActiveBg
                    btn.ForeColor = colActiveFg
                )
            )
            else
            (
                if btn.BackColor != colNormalBg do
                (
                    btn.BackColor = colNormalBg
                    btn.ForeColor = colNormalFg
                )
            )
        )

        -- Only update tooltips and button text when NOT actively dragging
        if not isDragging do
        (
            if toolTipObj == undefined do
                toolTipObj = dotnetobject "System.Windows.Forms.ToolTip"

            for i = 1 to 6 do
            (
                local v = presetValues[i]
                local btn = btns[i]
                btn.Text = formatAngleCaption v
                local tip = "L-Click: Apply " + (formatAngleCaption v) + "\n" + \
                            "R-Click: Save current (" + (formatAngleCaption curA) + ")\n" + \
                            "MMB: Reset default (" + (formatAngleCaption defaultPresetValues[i]) + ")"
                toolTipObj.SetToolTip btn tip
            )
        )
    )

    fn savePreset i val =
    (
        presetValues[i] = val
        rol_SelectCoplanar_SessionPresets[i] = val
    )

    fn layoutPresetButtons sideMargin:btnSideMargin btnGap:btnGap =
    (
        local btns = #(btn_p1, btn_p2, btn_p3, btn_p4, btn_p5, btn_p6)
        local n = btns.count
        local availableWidth = rol_SelectCoplanarTool.width - (sideMargin * 2)
        local totalGaps = (n - 1) * btnGap
        local btnWidth = ((availableWidth - totalGaps) / n) as integer
        local curY = btns[1].pos.y

        for i = 1 to n do
        (
            local w = btnWidth
            if i == n do w = availableWidth - ((n - 1) * (btnWidth + btnGap))
            local curX = sideMargin + (i - 1) * (btnWidth + btnGap)
            btns[i].pos = [curX, curY]
            btns[i].width = w
        )
    )

    fn resetPresetToDefault i =
    (
        local defVal = defaultPresetValues[i]
        savePreset i defVal
        updatePresetButtonsUI isDragging:false
        lbl_status.text = "Reset Preset " + (i as string) + " to default " + (defVal as string) + "°"
    )

    fn getTargetContext =
    (
        currentObj = undefined
        activeMod = undefined
        activeBase = undefined
        isEditPolyMod = false
        if selection.count != 1 do (contextKey = undefined; return false)
        local obj = selection[1]
        if not isValidNode obj do (contextKey = undefined; return false)
        local curMod = modPanel.getCurrentObject()
        if curMod == undefined do (contextKey = undefined; return false)
        if subObjectLevel != 2 and subObjectLevel != 4 do (contextKey = undefined; return false)

        if classOf curMod == Edit_Poly then
        (
            -- Resolve this modifier on this node, never the evaluated top of stack.
            if (findItem (for m in obj.modifiers collect m) curMod) == 0 do return false
            activeMod = curMod
            isEditPolyMod = true
        )
        else if (classOf curMod == Editable_Poly) and (curMod == obj.baseObject) then
            activeBase = obj.baseObject
        else (contextKey = undefined; return false)

        currentObj = obj
        isEdgeMode = subObjectLevel == 2
        local newKey = (getHandleByAnim obj as string) + ":" + (getHandleByAnim curMod as string) + ":" + (subObjectLevel as string)
        if newKey != contextKey do
        (
            seedList = #()
            expandedList = #()
            cachedNormals = #()
            lastScriptResultFaces = #{}
            contextKey = newKey
        )
        rad_dir.enabled = not isEdgeMode
        chk_connected.enabled = not isEdgeMode
        chk_sameElement.enabled = not isEdgeMode
        lbl_angle.text = if isEdgeMode then "Loop Turn Angle" else "Angle Threshold"
        true
    )

    fn componentLabel = (if isEdgeMode then "edges" else "faces")

    -- All topology queries use the active cage, including Edit Poly modifiers
    -- that change topology relative to the base object.
    fn cageVertex v =
        (if isEditPolyMod then activeMod.GetVertex v node:currentObj else polyOp.getVert activeBase v)

    fn cageEdgeVerts e =
        (if isEditPolyMod then #(activeMod.GetEdgeVertex e 1 node:currentObj, activeMod.GetEdgeVertex e 2 node:currentObj) else polyOp.getEdgeVerts activeBase e)

    fn cageFaceEdges obj f =
        (if isEditPolyMod then (for i = 1 to (activeMod.GetFaceDegree f node:currentObj) collect (activeMod.GetFaceEdge f i node:currentObj)) else polyOp.getFaceEdges activeBase f)

    fn cageFacesUsingEdges obj edges =
    (
        if not isEditPolyMod do return (polyOp.getFacesUsingEdge activeBase edges)
        local result = #{}
        local edgeSet = if classOf edges == Integer then #{edges} else edges
        for e in edgeSet do for side = 1 to 2 do
        (
            local f = activeMod.GetEdgeFace e side node:currentObj
            if f > 0 do result[f] = true
        )
        result
    )

    fn cageEdgesUsingFaces obj faces =
    (
        if not isEditPolyMod do return (polyOp.getEdgesUsingFace activeBase faces)
        local result = #{}
        local faceSet = if classOf faces == Integer then #{faces} else faces
        for f in faceSet do for e in (cageFaceEdges obj f) do result[e] = true
        result
    )

    fn cageElementsUsingFaces obj faces =
    (
        if not isEditPolyMod do return (polyOp.getElementsUsingFace activeBase faces)
        local result = copy faces
        local frontier = copy faces
        while not frontier.isEmpty do
        (
            frontier = (cageFacesUsingEdges obj (cageEdgesUsingFaces obj frontier)) - result
            result += frontier
        )
        result
    )

    fn cageVertexEdges v =
    (
        if not isEditPolyMod do return (polyOp.getEdgesUsingVert activeBase #{v})
        local result = #{}
        for i = 1 to (activeMod.GetVertexEdgeCount v node:currentObj) do
        (
            local e = activeMod.GetVertexEdge v i node:currentObj
            if e > 0 do result[e] = true
        )
        result
    )

    fn cageFaceNormal f =
    (
        if not isEditPolyMod do return (polyOp.getFaceNormal activeBase f)
        -- Newell normal preserves polygon winding and works for n-gons.
        local degree = activeMod.GetFaceDegree f node:currentObj
        local normal = [0,0,0]
        if degree < 3 do return normal
        for i = 1 to degree do
        (
            local a = cageVertex (activeMod.GetFaceVertex f i node:currentObj)
            local b = cageVertex (activeMod.GetFaceVertex f ((mod i degree) + 1) node:currentObj)
            normal += cross a b
        )
        if length normal > 0.000001 then normalize normal else [0,0,0]
    )

    fn getFaceSelectionFromObj =
    (
        try (
            if isEditPolyMod and activeMod != undefined then
                activeMod.GetSelection (if isEdgeMode then #Edge else #Face) node:currentObj
            else if isValidNode currentObj and activeBase != undefined then
                (if isEdgeMode then polyOp.getEdgeSelection activeBase else polyOp.getFaceSelection activeBase)
            else
                undefined
        ) catch (
            undefined
        )
    )

    fn updateCallbackRegistration state =
    (
        if state then
        (
            if rol_SelectCoplanar_NodeCallback == undefined do
            (
                rol_SelectCoplanar_NodeCallback = NodeEventCallback subobjectSelectionChanged:(
                    fn onSubSelEv ev sub = (
                        if rol_SelectCoplanarTool != undefined and rol_SelectCoplanarTool.open do
                            rol_SelectCoplanarTool.onViewportSelectionChanged()
                    )
                )
            )
        )
        else
        (
            rol_SelectCoplanar_NodeCallback = undefined
        )
    )

    fn setFaceSelectionToObj selBitArray =
    (
        if not getTargetContext() do return false

        -- Temporarily disable callback so our programmatic selection does not queue feedback events
        local cbWasActive = (rol_SelectCoplanar_NodeCallback != undefined)
        rol_SelectCoplanar_NodeCallback = undefined

        try (
            if isEditPolyMod and activeMod != undefined then
            (
                local level = if isEdgeMode then #Edge else #Face
                local oldSelection = activeMod.GetSelection level node:currentObj
                -- Select updates the modifier's live local selection. SetSelection
                -- alone can report success without changing it in Max 2025.
                activeMod.Select level &oldSelection select:false node:currentObj
                activeMod.Select level &selBitArray node:currentObj
            )
            else if activeBase != undefined then
            (
                if isEdgeMode then polyOp.setEdgeSelection activeBase selBitArray else polyOp.setFaceSelection activeBase selBitArray
            )
            lastScriptResultFaces = copy selBitArray
            redrawViews()
        ) catch ()

        -- Re-enable callback for user clicks
        if cbWasActive and chk_autoExpand.checked do
            updateCallbackRegistration true
    )

    fn cacheMeshData =
    (
        if not isValidNode currentObj do return false
        try (
            numFaces = if isEditPolyMod then activeMod.GetNumFaces node:currentObj else polyOp.getNumFaces activeBase
            cachedNormals = if isEdgeMode then #() else (for f = 1 to numFaces collect (cageFaceNormal f))

            -- Heavy mesh protection (>50,000 polygons): throttle to 1000ms if enabled
            if sld_angle != undefined do
            (
                if chk_throttle50k.checked and numFaces > 50000 then
                    sld_angle.ThrottleMs = 1000
                else
                    sld_angle.ThrottleMs = 25
            )
            return true
        ) catch (
            return false
        )
    )

    fn getEdgeMid obj e =
    (
        local v = cageEdgeVerts e
        ((cageVertex v[1]) + (cageVertex v[2])) / 2.0
    )

    -- Identifies opposite edge pairs for Row (Horizontal) and Column (Vertical)
    fn getRowColEdges obj startF =
    (
        local fe = cageFaceEdges obj startF
        if fe.count != 4 then
            #(fe, fe) -- fallback for non-quad
        else
        (
            local vA = (getEdgeMid obj fe[3]) - (getEdgeMid obj fe[1])
            local vB = (getEdgeMid obj fe[4]) - (getEdgeMid obj fe[2])
            local isPairA_Row = false

            if (abs (abs vA.z - abs vB.z) > 0.05) then
                isPairA_Row = (abs vA.z) < (abs vB.z)
            else
                isPairA_Row = (abs vA.y) < (abs vB.y)

            local rowE = if isPairA_Row then #(fe[1], fe[3]) else #(fe[2], fe[4])
            local colE = if isPairA_Row then #(fe[2], fe[4]) else #(fe[1], fe[3])
            #(rowE, colE)
        )
    )

    -- Steps along a directed quad strip across opposite edges
    fn stepFaceStrip obj startF startEdge matchedBitSet minCos:0.0 isRelative:false =
    (
        local res = #{startF}
        local curF = startF
        local curEdge = startEdge
        local finished = false

        while not finished do
        (
            local edgeFaces = (cageFacesUsingEdges obj curEdge) - #{curF}
            if edgeFaces.isEmpty then
            (
                finished = true
            )
            else
            (
                local nextF = (edgeFaces as array)[1]
                local canStep = false

                if isRelative then
                (
                    if not res[nextF] and nextF <= cachedNormals.count and curF <= cachedNormals.count do
                    (
                        local dotVal = dot cachedNormals[curF] cachedNormals[nextF]
                        if dotVal >= minCos do canStep = true
                    )
                )
                else
                (
                    if matchedBitSet[nextF] and not res[nextF] do canStep = true
                )

                if not canStep then
                (
                    finished = true
                )
                else
                (
                    res[nextF] = true
                    local nextFe = cageFaceEdges obj nextF
                    if nextFe.count != 4 then
                    (
                        finished = true
                    )
                    else
                    (
                        local enterIdx = findItem nextFe curEdge
                        if enterIdx == 0 then
                        (
                            finished = true
                        )
                        else
                        (
                            local oppIdx = mod (enterIdx + 1) 4 + 1
                            curEdge = nextFe[oppIdx]
                            curF = nextF
                        )
                    )
                )
            )
        )
        res
    )

    fn expandEdgeLoops seeds =
    (
        local result = copy seeds
        -- Zero keeps just the seeds, as in Polygon mode.
        if spn_angle.value <= 0.0001 do return result
        local minCos = cos spn_angle.value
        for seed in seeds do
        (
            local ends = cageEdgeVerts seed
            for endpoint in ends do
            (
                local curEdge = seed
                local atVertex = endpoint
                local otherVertex = if ends[1] == endpoint then ends[2] else ends[1]
                local seedDirection = (cageVertex atVertex) - (cageVertex otherVertex)
                if length seedDirection > 0.000001 do
                (
                    seedDirection = normalize seedDirection
                    local prevDirection = seedDirection
                    local visited = #{seed}
                    local finished = false
                    while not finished do
                    (
                        local incident = cageVertexEdges atVertex
                        local curFaces = cageFacesUsingEdges currentObj curEdge
                        local candidates = #{}
                        if curFaces.numberSet == 2 and incident.numberSet == 4 then
                        (
                            -- The loop continuation shares a vertex but no face.
                            for e in (incident - #{curEdge}) do
                                if ((cageFacesUsingEdges currentObj e) * curFaces).isEmpty do candidates[e] = true
                        )
                        else if curFaces.numberSet == 1 then
                        (
                            -- Follow an open boundary only when exactly two boundary edges meet.
                            local boundary = #{}
                            for e in incident do
                                if (cageFacesUsingEdges currentObj e).numberSet == 1 do boundary[e] = true
                            if boundary.numberSet == 2 do candidates = boundary - #{curEdge}
                        )
                        if candidates.numberSet != 1 then finished = true
                        else
                        (
                            local nextEdge = (candidates as array)[1]
                            if visited[nextEdge] then finished = true
                            else
                            (
                                local nextEnds = cageEdgeVerts nextEdge
                                local nextVertex = if nextEnds[1] == atVertex then nextEnds[2] else nextEnds[1]
                                local direction = (cageVertex nextVertex) - (cageVertex atVertex)
                                if length direction <= 0.000001 then finished = true
                                else
                                (
                                    direction = normalize direction
                                    local reference = if chk_recursive.checked then prevDirection else seedDirection
                                    if (dot reference direction) < (minCos - 0.000001) then finished = true
                                    else
                                    (
                                        result[nextEdge] = true
                                        visited[nextEdge] = true
                                        curEdge = nextEdge
                                        atVertex = nextVertex
                                        prevDirection = direction
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
        result
    )

    fn expandClusterFromSeed seedBitSet =
    (
        if seedBitSet.isEmpty do return #{}
        if isEdgeMode do return (expandEdgeLoops seedBitSet)
        if not isEdgeMode and cachedNormals.count != numFaces do (
            if not cacheMeshData() do return #{}
        )

        local angleThresh = spn_angle.value
        local minCos = cos angleThresh
        local isRecursive = chk_recursive.checked
        local isConnected = chk_connected.checked

        local seedNormals = #()
        for f in seedBitSet do
        (
            if f <= cachedNormals.count do
            (
                local n = cachedNormals[f]
                local isDup = false
                for rn in seedNormals while not isDup do
                (
                    if (dot n rn) > 0.9999 do isDup = true
                )
                if not isDup do append seedNormals n
            )
        )
        if seedNormals.count == 0 do return copy seedBitSet

        -- 1. Candidate faces (element filter)
        local candidateFaces = #{1..numFaces}
        if chk_sameElement.checked do
        (
            try (
                candidateFaces = cageElementsUsingFaces currentObj seedBitSet
            ) catch (
                candidateFaces = #{1..numFaces}
            )
        )

        -- 2. Non-recursive angle test against candidate faces
        local matchedFaces = #{}
        if not isRecursive then
        (
            local sCount = seedNormals.count
            for f in candidateFaces do
            (
                local curNorm = cachedNormals[f]
                local matchFound = false
                for r = 1 to sCount while not matchFound do
                (
                    if (dot seedNormals[r] curNorm) >= minCos do matchFound = true
                )
                if matchFound do matchedFaces[f] = true
            )
        )
        matchedFaces += seedBitSet

        -- 3. Connected flood or strip
        if isConnected then
        (
            if angleThresh <= 0.0001 then
            (
                matchedFaces = copy seedBitSet
            )
            else if rad_dir.state == 1 then
            (
                -- Mode 1: Surface flood fill
                local currentCluster = copy seedBitSet
                local border = copy currentCluster
                local finished = false

                try (
                    while not finished do
                    (
                        local borderEdges = cageEdgesUsingFaces currentObj border
                        local neighborFaces = cageFacesUsingEdges currentObj borderEdges
                        local newFaces = #{}

                        if isRecursive then
                        (
                            local candNeighbors = (neighborFaces * candidateFaces) - currentCluster
                            if candNeighbors.isEmpty then
                                finished = true
                            else
                            (
                                for bFace in border do
                                (
                                    if bFace <= cachedNormals.count do
                                    (
                                        local bNorm = cachedNormals[bFace]
                                        local bEdges = cageEdgesUsingFaces currentObj bFace
                                        local bAdjFaces = (cageFacesUsingEdges currentObj bEdges) * candNeighbors

                                        for adjF in bAdjFaces do
                                        (
                                            if adjF <= cachedNormals.count do
                                            (
                                                if (dot bNorm cachedNormals[adjF]) >= minCos do newFaces[adjF] = true
                                            )
                                        )
                                    )
                                )
                                if newFaces.isEmpty then finished = true
                                else
                                (
                                    currentCluster += newFaces
                                    border = newFaces
                                )
                            )
                        )
                        else
                        (
                            newFaces = (neighborFaces * matchedFaces) - currentCluster
                            if newFaces.isEmpty then finished = true
                            else
                            (
                                currentCluster += newFaces
                                border = newFaces
                            )
                        )
                    )
                    matchedFaces = currentCluster
                ) catch (
                    matchedFaces = copy seedBitSet
                )
            )
            else
            (
                -- Mode 2 (Row) or Mode 3 (Column) Directed Strip
                local isRow = (rad_dir.state == 2)
                local currentCluster = copy seedBitSet

                try (
                    for startF in seedBitSet do
                    (
                        local pairRes = getRowColEdges currentObj startF
                        local targetEdges = if isRow then pairRes[1] else pairRes[2]

                        for e in targetEdges do
                        (
                            local strip = stepFaceStrip currentObj startF e matchedFaces minCos:minCos isRelative:isRecursive
                            currentCluster += strip
                        )
                    )
                    matchedFaces = currentCluster
                ) catch (
                    matchedFaces = copy seedBitSet
                )
            )
        )
        else if angleThresh <= 0.0001 then
        (
            matchedFaces = copy seedBitSet
        )

        matchedFaces
    )

    fn syncReferenceFromSelection forceUpdate:false customSeed:undefined =
    (
        if not getTargetContext() do
        (
            if selection.count == 0 then
            (
                lbl_target.text = "Target: None"
                lbl_status.text = "Select an object in viewport"
            )
            else if selection.count > 1 then
            (
                lbl_target.text = "Target: Multiple selected"
                lbl_status.text = "Select a single object"
            )
            else
            (
                local curMod = modPanel.getCurrentObject()
                local modName = if curMod != undefined then (classOf curMod as string) else "Unknown"
                if subObjectLevel != 2 and subObjectLevel != 4 then
                (
                    lbl_target.text = "Target: " + (if isValidNode selection[1] then selection[1].name else "None")
                    lbl_status.text = "Inactive: switch to Polygon or Edge mode"
                )
                else
                (
                    lbl_target.text = "Target: " + modName + " (Unsupported)"
                    lbl_status.text = "Inactive: requires Edit Poly or base Editable Poly"
                )
            )
            return false
        )

        lbl_target.text = "Target: " + currentObj.name

        local curSel = getFaceSelectionFromObj()
        if curSel == undefined or curSel.isEmpty then
        (
            lbl_status.text = "No " + (componentLabel()) + " selected in viewport"
            seedList = #()
            expandedList = #()
            lastScriptResultFaces = #{}
            return false
        )

        local seedFaces = if customSeed != undefined then customSeed else curSel
        local isNewSelection = forceUpdate or (customSeed != undefined) or (curSel != lastScriptResultFaces) or (seedList.count == 0)

        if isNewSelection do
        (
            if not cacheMeshData() do return false
            if customSeed == undefined do
            (
                seedList = #(copy seedFaces)
                expandedList = #()
            )
            local throttleInfo = if (chk_throttle50k.checked and numFaces > 50000) then " [>50k: 1s throttle]" else ""
            lbl_status.text = "Base: " + (seedFaces.numberSet as string) + " " + (componentLabel()) + " locked" + throttleInfo
        )
        return true
    )

    fn applyAngleSelection isInteractive:false =
    (
        if not syncReferenceFromSelection() do return false
        if not isEdgeMode and cachedNormals.count != numFaces do (
            if not cacheMeshData() do return false
        )

        -- If seedList is empty, seed from current selection
        if seedList.count == 0 do
        (
            local curSel = getFaceSelectionFromObj()
            if curSel != undefined and not curSel.isEmpty do
                seedList = #(copy curSel)
        )

        -- Recompute expansion for each island independently
        expandedList = #()
        local allExpanded = #{}
        for s in seedList do
        (
            local cluster = expandClusterFromSeed s
            append expandedList cluster
            allExpanded += cluster
        )

        -- Combine with existing selection depending on Mode
        local baseSel = getFaceSelectionFromObj()
        if baseSel == undefined do baseSel = #{}
        local finalSel = #{}

        case rad_mode.state of
        (
            1: finalSel = allExpanded
            2: finalSel = baseSel + allExpanded
            3: finalSel = baseSel - allExpanded
        )

        if isInteractive then
        (
            with undo off
            (
                setFaceSelectionToObj finalSel
            )
        )
        else
        (
            with undo "Select by Angle" on
            (
                setFaceSelectionToObj finalSel
            )
        )

        local throttleNote = if (chk_throttle50k.checked and numFaces > 50000) then " [>50k: 1s throttle]" else ""
        lbl_status.text = "Selected: " + (finalSel.numberSet as string) + " " + (componentLabel()) + throttleNote
    )

    -- Viewport selection callback: only active when user explicitly enables it
    fn onViewportSelectionChanged =
    (
        if not chk_autoExpand.checked do return ()
        if not getTargetContext() do
        (
            syncReferenceFromSelection()
            return ()
        )

        local curSel = getFaceSelectionFromObj()
        if curSel == undefined or curSel.isEmpty do
        (
            seedList = #()
            expandedList = #()
            lastScriptResultFaces = #{}
            return ()
        )

        -- Handle Undo/Redo: gracefully accept viewport selection without auto-expanding or re-triggering
        if rol_SelectCoplanar_IsUndoing do
        (
            rol_SelectCoplanar_IsUndoing = false
            lastScriptResultFaces = copy curSel
            seedList = #(copy curSel)
            expandedList = #()
            syncReferenceFromSelection forceUpdate:true customSeed:curSel
            return ()
        )

        -- If the selection matches our last script output, ignore
        if curSel == lastScriptResultFaces do return ()

        -- Detect modifier keys
        local isCtrl = keyboard.controlPressed
        local isAlt = keyboard.altPressed

        -- If neither Ctrl nor Alt, but rad_mode specifies Add/Subtract
        if not isCtrl and not isAlt do
        (
            if rad_mode.state == 2 do isCtrl = true
            if rad_mode.state == 3 do isAlt = true
        )

        -- Determine the newly clicked / added face(s)
        local diffAdded = if (lastScriptResultFaces != undefined and not lastScriptResultFaces.isEmpty) then
            curSel - lastScriptResultFaces
        else
            curSel

        if isCtrl then
        (
            -- ADD Island: only grow from newly clicked face(s)
            local newSeed = if not diffAdded.isEmpty then diffAdded else curSel
            if not cacheMeshData() do return ()

            local newCluster = expandClusterFromSeed newSeed
            append seedList newSeed
            append expandedList newCluster

            local finalSel = copy lastScriptResultFaces
            finalSel += newCluster

            with undo "Select by Angle (Add)" on
            (
                setFaceSelectionToObj finalSel
            )
            local throttleNote = if (chk_throttle50k.checked and numFaces > 50000) then " [>50k: 1s throttle]" else ""
            lbl_status.text = "Added island: " + (newCluster.numberSet as string) + " " + (componentLabel()) + " (Total: " + (finalSel.numberSet as string) + ")" + throttleNote
        )
        else if isAlt then
        (
            -- SUBTRACT Island: determine what was unselected or clicked
            local diffRemoved = if (lastScriptResultFaces != undefined and not lastScriptResultFaces.isEmpty) then
                lastScriptResultFaces - curSel
            else
                #{}

            local seedToRemove = if not diffRemoved.isEmpty then diffRemoved else curSel
            if not cacheMeshData() do return ()

            local clusterToRemove = expandClusterFromSeed seedToRemove
            local finalSel = if (lastScriptResultFaces != undefined and not lastScriptResultFaces.isEmpty) then
                lastScriptResultFaces - clusterToRemove
            else
                curSel - clusterToRemove

            -- Remove seeds that intersect with subtracted region
            local updatedSeeds = #()
            local updatedExpanded = #()
            for i = 1 to seedList.count do
            (
                if (seedList[i] * clusterToRemove).isEmpty do
                (
                    append updatedSeeds seedList[i]
                    append updatedExpanded (expandedList[i] - clusterToRemove)
                )
            )
            seedList = updatedSeeds
            expandedList = updatedExpanded

            with undo "Select by Angle (Subtract)" on
            (
                setFaceSelectionToObj finalSel
            )
            local throttleNote = if (chk_throttle50k.checked and numFaces > 50000) then " [>50k: 1s throttle]" else ""
            lbl_status.text = "Subtracted island: " + (clusterToRemove.numberSet as string) + " " + (componentLabel()) + " (Remaining: " + (finalSel.numberSet as string) + ")" + throttleNote
        )
        else
        (
            -- REPLACE (Fresh single seed / selection)
            local freshSeed = if not diffAdded.isEmpty then diffAdded else curSel
            seedList = #(copy freshSeed)
            expandedList = #()

            syncReferenceFromSelection forceUpdate:true customSeed:freshSeed
            applyAngleSelection isInteractive:false
        )
    )

    -- Preset Actions: Left-click applies, Right-click saves, Middle-click resets
    fn setPresetFromCurrent i =
    (
        local curAngle = spn_angle.value
        savePreset i curAngle
        updatePresetButtonsUI isDragging:false
        lbl_status.text = "Saved " + (curAngle as string) + "° to Preset " + (i as string)
    )

    fn applyPreset i =
    (
        local targetAngle = presetValues[i]
        spn_angle.value = targetAngle
        sld_angle.SetValueSilent targetAngle
        applyAngleSelection isInteractive:false
        updatePresetButtonsUI isDragging:false
    )

    fn handlePresetClick i mouseBtn =
    (
        if mouseBtn == mouseButtonsClass.Left then
            applyPreset i
        else if mouseBtn == mouseButtonsClass.Right then
            setPresetFromCurrent i
        else if mouseBtn == mouseButtonsClass.Middle then
            resetPresetToDefault i
    )

    on btn_p1 MouseDown sender args do handlePresetClick 1 args.Button
    on btn_p2 MouseDown sender args do handlePresetClick 2 args.Button
    on btn_p3 MouseDown sender args do handlePresetClick 3 args.Button
    on btn_p4 MouseDown sender args do handlePresetClick 4 args.Button
    on btn_p5 MouseDown sender args do handlePresetClick 5 args.Button
    on btn_p6 MouseDown sender args do handlePresetClick 6 args.Button

    on spn_angle changed val do
    (
        sld_angle.SetValueSilent val
        applyAngleSelection isInteractive:false
        updatePresetButtonsUI isDragging:false
    )

    on sld_angle ValueChanged sender args do
    (
        spn_angle.value = sld_angle.Value
        applyAngleSelection isInteractive:true
        updatePresetButtonsUI isDragging:true
    )

    on sld_angle DragEnded sender args do
    (
        -- Commit a single clean undo record when dragging finishes
        if lastScriptResultFaces != undefined and not lastScriptResultFaces.isEmpty do
        (
            with undo "Select by Angle" on
            (
                setFaceSelectionToObj lastScriptResultFaces
            )
        )
        updatePresetButtonsUI isDragging:false
    )

    on rad_dir changed state do
    (
        applyAngleSelection isInteractive:false
    )

    on chk_autoExpand changed state do
    (
        updateCallbackRegistration state
    )

    on chk_throttle50k changed state do
    (
        if sld_angle != undefined do
        (
            if state and numFaces > 50000 then
                sld_angle.ThrottleMs = 1000
            else
                sld_angle.ThrottleMs = 25
        )
    )

    on chk_connected changed state do
    (
        applyAngleSelection isInteractive:false
    )

    on chk_recursive changed state do
    (
        applyAngleSelection isInteractive:false
    )

    on chk_sameElement changed state do
    (
        applyAngleSelection isInteractive:false
    )

    on rad_mode changed state do
    (
        applyAngleSelection isInteractive:false
    )

    on rol_SelectCoplanarTool open do
    (
        local flatStyle = (dotnetClass "System.Windows.Forms.FlatStyle").Flat
        local btnFont = dotnetobject "System.Drawing.Font" "Segoe UI" 8.5 (dotnetClass "System.Drawing.FontStyle").Regular
        local handCursor = (dotnetClass "System.Windows.Forms.Cursors").Hand
        local btns = #(btn_p1, btn_p2, btn_p3, btn_p4, btn_p5, btn_p6)

        for b in btns do
        (
            b.FlatStyle = flatStyle
            b.FlatAppearance.BorderSize = 0
            b.Font = btnFont
            b.Cursor = handCursor
            b.Margin = dotnetobject "System.Windows.Forms.Padding" 1
            b.Padding = dotnetobject "System.Windows.Forms.Padding" 0
        )

        layoutPresetButtons()

        sld_angle.Value = spn_angle.value
        updatePresetButtonsUI isDragging:false
        syncReferenceFromSelection forceUpdate:true

        -- Register Undo / Redo tracking callbacks
        callbacks.removeScripts id:#AgSelectCoplanarUndo
        callbacks.addScript #sceneUndo "rol_SelectCoplanar_IsUndoing = true" id:#AgSelectCoplanarUndo
        callbacks.addScript #sceneRedo "rol_SelectCoplanar_IsUndoing = true" id:#AgSelectCoplanarUndo

        -- Register callback ONLY if chk_autoExpand is explicitly enabled
        updateCallbackRegistration chk_autoExpand.checked
    )

    on rol_SelectCoplanarTool close do
    (
        -- Always cleanly unregister callbacks on tool close
        updateCallbackRegistration false
        callbacks.removeScripts id:#AgSelectCoplanarUndo
    )
)

-- Launch directly; MaxPkg owns the package button and installation.
createDialog rol_SelectCoplanarTool


