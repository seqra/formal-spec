import Lean
import Lean.Meta.Match.MatcherInfo
import Lean.Structure
import Lean.Util.FoldConsts

/-!
  Deterministic descriptions derived from elaborated Lean declarations.

  A module namespace defines the public surface. The renderer discovers direct
  declarations in that namespace, derives meanings and vocabulary from their
  types, values, fields, constructors, and dependencies, then emits prose-only
  per-file specifications. Generated helper declarations are excluded.
-/

namespace LibSpec.Description

open Lean Elab Term Meta

syntax (name := describeAs) "describeAs" str : attr

initialize describeAsAttr : ParametricAttribute String ← registerParametricAttribute {
  name := `describeAs
  descr := "optional natural-language name for a formal declaration"
  getParam := fun _ stx =>
    match stx[1].isStrLit? with
    | some value => pure value
    | none => throwErrorAt stx "describeAs expects a string literal"
}

private def nameParts : Name → List String
  | .anonymous => []
  | .str parent part => nameParts parent ++ [part]
  | .num parent part => nameParts parent ++ [toString part]

private def humanize (value : String) : String :=
  let rec loop (previousLower : Bool) : List Char → List Char
    | [] => []
    | char :: rest =>
        if char == '_' || char == '-' then
          ' ' :: loop false rest
        else if char.isUpper && previousLower then
          ' ' :: char.toLower :: loop false rest
        else
          char.toLower :: loop char.isLower rest
  String.ofList (loop false value.toList)

private def capitalize (value : String) : String :=
  match value.toList with
  | [] => value
  | first :: rest => String.ofList (first.toUpper :: rest)

private def suffixLabel (name : Name) (depth : Nat) : String :=
  let parts := nameParts name
  String.intercalate " " <| (parts.drop (parts.length - min depth parts.length)).map humanize

private def contextualName (env : Environment) (context : Array Name) (name : Name) : String :=
  match describeAsAttr.getParam? env name with
  | some override => override
  | none =>
      let maximum := (nameParts name).length
      let depths := (List.range maximum).map (· + 1)
      let uniqueAt (depth : Nat) : Bool :=
        let candidate := suffixLabel name depth
        context.all fun other => other == name || suffixLabel other depth != candidate
      match depths.find? uniqueAt with
      | some depth => suffixLabel name depth
      | none => name.toString

private def isSemanticName (roots : Array Name) (name : Name) : Bool :=
  roots.any (fun root => root.getPrefix.isPrefixOf name) || (`LibSpec).isPrefixOf name

private def isGeneratedName (name : Name) : Bool :=
  let rendered := name.toString
  let leaf := nameParts name |>.getLast?.getD ""
  leaf.startsWith "inst" || leaf.startsWith "_" ||
    rendered.contains ".match_" || rendered.contains "._proof_" ||
    rendered.contains ".eq_" || rendered.contains ".sizeOf_" ||
    leaf == "rec" || leaf == "recOn" || leaf == "casesOn" ||
    leaf == "noConfusion" || leaf == "noConfusionType" ||
    leaf == "ctorIdx" || leaf == "ctorElim" || leaf == "ctorElimType"

private def isPublicDeclaration (root name : Name) (info : ConstantInfo) : Bool :=
  name.getPrefix == root && !isGeneratedName name &&
    match info with
    | .defnInfo _ | .thmInfo _ | .opaqueInfo _ | .inductInfo _ => true
    | _ => false

private def semanticReferences (roots : Array Name) (env : Environment)
    (info : ConstantInfo) : Array Name := Id.run do
  let mut references := #[]
  let used := match info with
    | .thmInfo _ => info.type.getUsedConstantsAsSet
    | .inductInfo _ => ({} : NameSet)
    | _ => info.getUsedConstantsAsSet
  for name in used do
    if isSemanticName roots name && name != info.name && !isGeneratedName name && env.contains name then
      match env.find? name with
      | some (.ctorInfo _) => pure ()
      | _ => references := references.push name
  references.qsort Name.quickLt

private partial def renderTypeNoun (env : Environment) (context : Array Name) (expression : Expr) : TermElabM String := do
  let expression ← whnf expression
  match expression with
  | .sort .zero => return "a proposition"
  | .sort _ => return "a type"
  | .forallE binder domain body binderInfo =>
      withLocalDecl binder binderInfo domain fun localValue => do
        let domainNoun ← renderTypeNoun env context domain
        let resultNoun ← renderTypeNoun env context (body.instantiate1 localValue)
        return s!"a function from {domainNoun} to {resultNoun}"
  | _ =>
      match expression.getAppFnArgs with
      | (name, args) =>
          if name.isAnonymous then
            return "a value"
          if name == ``Option then
            if _h : args.size > 0 then
              return "an optional " ++ (← renderTypeNoun env context args[args.size - 1]!).replace "a " ""
            else return "an optional value"
          if name == ``Nat then return "a natural number"
          if name == ``Bool then return "a Boolean value"
          if name == ``String then return "text"
          if name == `LibSpec.TransitionSystem && args.size == 2 then
            let state ← renderTypeNoun env context args[0]!
            let input ← renderTypeNoun env context args[1]!
            return s!"a transition system over {state}, driven by {input}"
          return "a " ++ contextualName env context name

private partial def renderExpression (roots : Array Name) (env : Environment) (context : Array Name)
    (expression : Expr) : TermElabM (Option String) := do
  if let some value := expression.rawNatLit? then return some (toString value)
  if let some value ← getNatValue? expression then return some (toString value)
  match expression with
  | .lit (.natVal value) => return some (toString value)
  | .lit (.strVal value) => return some s!"“{value}”"
  | .fvar id => return some (humanize (← id.getUserName).toString)
  | .const name _ =>
      if name == ``True then return some "true"
      if name == ``False then return some "false"
      if isSemanticName roots name then return some (contextualName env context name)
      return none
  | .forallE binder domain body binderInfo =>
      withLocalDecl binder binderInfo domain fun localValue => do
        let renderedBody ← renderExpression roots env context (body.instantiate1 localValue)
        let some renderedBody := renderedBody | return none
        if !body.hasLooseBVar 0 && (← isProp domain) then
          let some renderedDomain ← renderExpression roots env context domain | return none
          return some s!"if {renderedDomain}, then {renderedBody}"
        let binderLabel := humanize binder.toString
        let domainLabel ← renderTypeNoun env context domain
        return some s!"for every {binderLabel}, {domainLabel}, {renderedBody}"
  | .app .. =>
      let (name, arguments) := expression.getAppFnArgs
      if let some matcherInfo := getMatcherInfoCore? env name then
        if matcherInfo.numDiscrs == 1 then
          let discriminatorPosition := matcherInfo.getFirstDiscrPos
          if _h : discriminatorPosition < arguments.size then
            let discriminator := arguments[discriminatorPosition]
            let discriminatorType ← whnf (← inferType discriminator)
            let (inductiveName, _) := discriminatorType.getAppFnArgs
            if let some (.inductInfo inductiveInfo) := env.find? inductiveName then
              if inductiveInfo.ctors.length == matcherInfo.numAlts then
                let mut cases := []
                let alternativePosition := matcherInfo.getFirstAltPos
                for index in List.range matcherInfo.numAlts do
                  if _alt : alternativePosition + index < arguments.size then
                    let branch := arguments[alternativePosition + index]
                    let some renderedBranch ← renderExpression roots env context branch | return none
                    let constructor := inductiveInfo.ctors[index]!
                    let constructorLabel := contextualName env inductiveInfo.ctors.toArray constructor
                    cases := cases ++ [s!"when {constructorLabel}, {renderedBranch}"]
                  else return none
                return some <| String.intercalate "; " cases
      if name == ``Eq && arguments.size == 3 then
        let some left ← renderExpression roots env context arguments[1]! | return none
        let some right ← renderExpression roots env context arguments[2]! | return none
        return some s!"{left} equals {right}"
      if name == ``And && arguments.size == 2 then
        let some left ← renderExpression roots env context arguments[0]! | return none
        let some right ← renderExpression roots env context arguments[1]! | return none
        return some s!"{left}, and {right}"
      if name == ``Or && arguments.size == 2 then
        let some left ← renderExpression roots env context arguments[0]! | return none
        let some right ← renderExpression roots env context arguments[1]! | return none
        return some s!"{left}, or {right}"
      if name == ``Iff && arguments.size == 2 then
        let some left ← renderExpression roots env context arguments[0]! | return none
        let some right ← renderExpression roots env context arguments[1]! | return none
        return some s!"{left} exactly when {right}"
      if name == ``Not && arguments.size == 1 then
        let some value ← renderExpression roots env context arguments[0]! | return none
        return some s!"it is not the case that {value}"
      if name == ``Ne && arguments.size == 3 then
        let some left ← renderExpression roots env context arguments[1]! | return none
        let some right ← renderExpression roots env context arguments[2]! | return none
        return some s!"{left} does not equal {right}"
      if name == ``Option.some && arguments.size == 2 then
        return ← renderExpression roots env context arguments[1]!
      if name == ``Option.none then return some "no value"
      if name == ``Nat.add && arguments.size == 2 then
        let some left ← renderExpression roots env context arguments[0]! | return none
        let some right ← renderExpression roots env context arguments[1]! | return none
        return some s!"{left} plus {right}"
      if name == `HAdd.hAdd && arguments.size >= 2 then
        let some left ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some right ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{left} plus {right}"
      if name == `LibSpec.TransitionSystem.Reachable && arguments.size >= 2 then
        let some system ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some state ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{state} is reachable through {system}"
      if name == `LibSpec.TransitionSystem.Preserves && arguments.size >= 2 then
        let some system ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some property ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{system} preserves {property} after every permitted transition"
      if isSemanticName roots name && !isGeneratedName name then
        if let some (.ctorInfo constructor) := env.find? name then
          if let some structureInfo := getStructureInfo? env constructor.induct then
            let fieldArguments := arguments.toList.drop (arguments.size - structureInfo.fieldNames.size)
            let pairs := structureInfo.fieldNames.toList.zip fieldArguments
            let mut renderedFields := []
            for (field, value) in pairs do
              let some renderedValue ← renderExpression roots env context value | return none
              let fieldLabel := contextualName env structureInfo.fieldNames field
              renderedFields := renderedFields ++ [s!"{fieldLabel} equals {renderedValue}"]
            let structureLabel := contextualName env context constructor.induct
            return some <| structureLabel ++ " where " ++ String.intercalate ", " renderedFields
        let renderedArguments ← arguments.filterMapM (renderExpression roots env context)
        let label := contextualName env context name
        if renderedArguments.isEmpty then return some label
        return some <| label ++ " of " ++ String.intercalate ", " renderedArguments.toList
      match expression.getAppFn with
      | .fvar id =>
          let functionLabel := humanize (← id.getUserName).toString
          let renderedArguments ← expression.getAppArgs.filterMapM (renderExpression roots env context)
          if renderedArguments.isEmpty then return some functionLabel
          return some <| functionLabel ++ " of " ++ String.intercalate ", " renderedArguments.toList
      | _ => pure ()
      return none
  | .lam binder domain body binderInfo =>
      withLocalDecl binder binderInfo domain fun localValue =>
        renderExpression roots env context (body.instantiate1 localValue)
  | .letE binder type value body _ =>
      withLetDecl binder type value fun localValue =>
        renderExpression roots env context (body.instantiate1 localValue)
  | .mdata _ body | .proj _ _ body => renderExpression roots env context body
  | _ => return none

private def returnsProp (type : Expr) : TermElabM Bool :=
  forallTelescopeReducing type fun _ result => do
    match ← whnf result with
    | .sort .zero => return true
    | _ => return false

private def declarationMeaning (roots : Array Name) (env : Environment) (context : Array Name)
    (info : ConstantInfo) : TermElabM String := do
  let label := contextualName env context info.name
  match info with
  | .inductInfo value =>
      match getStructureInfo? env value.name with
      | some structureInfo =>
          let fields := structureInfo.fieldNames.map fun field => contextualName env structureInfo.fieldNames field
          return s!"{label} records {String.intercalate ", " fields.toList}."
      | none =>
          let constructors := value.ctors.toArray.map fun constructor => contextualName env value.ctors.toArray constructor
          return s!"{label} has the possible cases {String.intercalate ", " constructors.toList}."
  | .thmInfo _ =>
      match ← renderExpression roots env context info.type with
      | some proposition => return s!"{label} proves that {proposition}."
      | none => return "Description unavailable: this theorem uses a logical form the renderer does not yet understand."
  | .defnInfo _ | .opaqueInfo _ =>
      if ← returnsProp info.type then
        match info.value? (allowOpaque := true) with
        | some value =>
            match ← renderExpression roots env context value with
            | some meaning => return s!"{label} means {meaning}."
            | none => return "Description unavailable: this definition uses a logical form the renderer does not yet understand."
        | none => return "Description unavailable: the definition body is not available to the renderer."
      else
        match info.value? (allowOpaque := true) with
        | some value =>
            match ← renderExpression roots env context value with
            | some meaning => return s!"{label} means {meaning}."
            | none =>
                let noun ← forallTelescopeReducing info.type fun _ result => renderTypeNoun env context result
                return s!"{label} defines {noun}."
        | none =>
            let noun ← forallTelescopeReducing info.type fun _ result => renderTypeNoun env context result
            return s!"{label} defines {noun}."
  | _ => return "Description unavailable: this declaration kind is not supported."

private def declarationsIn (env : Environment) (root : Name) : Array ConstantInfo := Id.run do
  let mut declarations := #[]
  for (name, info) in env.constants.toList do
    if isPublicDeclaration root name info then declarations := declarations.push info
  declarations.qsort fun left right => Name.quickLt left.name right.name

private def moduleFor (env : Environment) (name : Name) : Name :=
  match env.getModuleIdxFor? name with
  | some index => env.header.moduleNames[index.toNat]!
  | none => env.mainModule

private def modulePath (module : Name) (extension : String) : String :=
  String.intercalate "/" (nameParts module) ++ extension

private def repeatParent (count : Nat) : String :=
  String.join (List.replicate count "../")

private def moduleTitle (root module : Name) : String :=
  let subject := humanize <| (nameParts module).getLast?.getD module.toString
  let category := match (nameParts root).getLast? with
    | some "Spec" => "specification"
    | some "Model" => "model"
    | some "Proof" => "proofs"
    | _ => "formal description"
  capitalize subject ++ " " ++ category

private def readableMeaning (meaning : String) : String :=
  meaning
    |>.replace "spec revision" "specification revision"
    |>.replace "proof revision of before equals specification revision of before"
      "a proof is recorded for the current specification revision"
    |>.replace "tests revision of before equals specification revision of before"
      "model-derived tests are recorded for the current specification revision"
    |>.replace " equals no value" " is not recorded"

private def withoutFinalPeriod (value : String) : String :=
  if value.endsWith "." then (value.dropEnd 1).toString else value

private def splitOnce (value separator : String) : Option (String × String) :=
  match value.splitOn separator with
  | [] | [_] => none
  | first :: rest => some (first, String.intercalate separator rest)

private def withoutPrefix (leading value : String) : String :=
  if value.startsWith leading then (value.drop leading.length).toString else value

private def bullets (values : List String) : String :=
  String.intercalate "\n" <| values.map fun value => "- " ++ capitalize (readableMeaning value)

private def conjuncts (value : String) : List String :=
  value.splitOn ", and "

private def renderClaim (claim : String) : String :=
  let claim := readableMeaning claim
  let (scope?, claim) :=
    if claim.startsWith "for every " then
      match splitOnce claim ", if " with
      | some (scope, rest) => (some (withoutPrefix "for every " scope), "if " ++ rest)
      | none => (some (withoutPrefix "for every " claim), "")
    else (none, claim)
  let implicationParts := claim.splitOn ", then "
  let scopeSection := match scope? with
    | some scope => "**Scope**\n\n" ++ capitalize scope ++ ".\n\n"
    | none => ""
  if implicationParts.length > 1 then
    let conditions := implicationParts.dropLast.map (withoutPrefix "if " ·)
    let result := implicationParts.getLast?.getD ""
    scopeSection ++ "**Given**\n\n" ++ bullets conditions ++
      "\n\n**Guarantee**\n\n" ++ bullets (conjuncts result)
  else if claim.startsWith "it is not the case that " then
    scopeSection ++ "**Excluded case**\n\n" ++
      capitalize (withoutPrefix "it is not the case that " claim)
  else
    scopeSection ++ "**Established**\n\n" ++ bullets (conjuncts claim)

private def renderRule (label meaning : String) : Option String := do
  let body ← (splitOnce meaning (label ++ " means ")).map (·.2)
  if !body.startsWith "if " then none else
  let parts := body.splitOn ", then "
  if parts.length < 2 then none else
  let conditions := parts.dropLast.map (withoutPrefix "if " ·)
  let guarantees := conjuncts (parts.getLast?.getD "")
  some <| "**Applies when**\n\n" ++ bullets conditions ++
    "\n\n**Must hold**\n\n" ++ bullets guarantees

private def renderAppliedDefinition (label meaning : String) : Option String := do
  let body ← (splitOnce meaning (label ++ " means ")).map (·.2)
  let (definition, arguments) ← splitOnce body " of "
  let arguments := arguments.splitOn ", "
  if arguments.length < 2 then none else
  return "**Definition**\n\nApplies " ++ readableMeaning definition ++ " using:\n\n" ++
    bullets arguments

private def recordParts (value : String) : Option (String × List (String × String)) := do
  let (record, fields) ← splitOnce value " where "
  let rows ← fields.splitOn ", " |>.mapM fun field =>
    match splitOnce field " equals " with
    | some pair => some (pair.1, withoutFinalPeriod pair.2)
    | none => (splitOnce field " is not recorded").map fun pair => (pair.1, "not recorded")
  return (record, rows)

private def renderRecordTable (value column : String) : Option String := do
  let (_, fields) ← recordParts (readableMeaning value)
  let rows := fields.map fun (field, fieldValue) =>
    "| " ++ capitalize field ++ " | " ++ capitalize fieldValue ++ " |"
  return "| Field | " ++ column ++ " |\n| --- | --- |\n" ++ String.intercalate "\n" rows

private def renderTransitionEffect (field value : String) : String :=
  let field := readableMeaning field
  let value := readableMeaning value
  if value == field ++ " of before" then "Unchanged"
  else if value == "no value" || value == "not recorded" then "Cleared"
  else if value == field ++ " of before plus 1" then "Incremented by 1"
  else if value == "specification revision of before" then "Set to current specification revision"
  else capitalize value

private def renderStateClaim (claim : String) : Option String := do
  let claim := readableMeaning claim
  let excluded := claim.startsWith "it is not the case that "
  let body := if excluded then withoutPrefix "it is not the case that " claim else claim
  if body.startsWith "workflow invariant of " then
    let state := withoutPrefix "workflow invariant of " body
    let table ← renderRecordTable state "Value"
    let result := if excluded then "The workflow invariant does not hold." else "The workflow invariant holds."
    return "**State under review**\n\n" ++ table ++ "\n\n**Result**\n\n- " ++ result
  let (state, system) ← splitOnce body " is reachable through "
  let table ← renderRecordTable state "Value"
  let result := if excluded then
      "This state cannot be reached through " ++ withoutFinalPeriod system ++ "."
    else
      "This state is reachable through " ++ withoutFinalPeriod system ++ "."
  return "**State under review**\n\n" ++ table ++ "\n\n**Result**\n\n- " ++ result

private def renderTransitionCase (value : String) : Option String := do
  let (event, body) ← splitOnce value ", "
  let (requirements, after) := match splitOnce body ", and after equals " with
    | some pair => pair
    | none => match splitOnce body "after equals " with
      | some (_, after) => ("", after)
      | none => ("", "")
  if after.isEmpty then none else
  let (_, fields) ← recordParts (readableMeaning after)
  let requirementSection := if requirements.isEmpty then
      "**Preconditions**\n\nNone."
    else
      "**Preconditions**\n\n" ++ bullets (conjuncts requirements)
  let rows := fields.map fun (field, fieldValue) =>
    "| " ++ capitalize field ++ " | " ++ renderTransitionEffect field fieldValue ++ " |"
  return "### " ++ capitalize event ++ "\n\n" ++ requirementSection ++
    "\n\n**Effects**\n\n| Field | After transition |\n| --- | --- |\n" ++
    String.intercalate "\n" rows

private def renderTransitionSystem (label meaning : String) : Option String := do
  let body ← (splitOnce meaning (label ++ " means transition system where initial equals ")).map (·.2)
  let (initial, transitions) ← splitOnce body ", step equals "
  let cases := transitions.splitOn "; when "
  let cases := match cases with
    | [] => []
    | first :: rest => withoutPrefix "when " first :: rest
  let renderedCases ← cases.mapM renderTransitionCase
  return "A state machine governing the permitted workflow.\n\n" ++
    "**Initial condition**\n\n- " ++ capitalize (readableMeaning initial) ++
    ".\n\n" ++ String.intercalate "\n\n" renderedCases

private def renderDeclarationMarkdown (roots : Array Name) (env : Environment)
    (context : Array Name) (info : ConstantInfo) : TermElabM String := do
  let label := contextualName env context info.name
  let meaning ← declarationMeaning roots env context info
  match info with
  | .inductInfo value =>
      match getStructureInfo? env value.name with
      | some structureInfo =>
          let mut rows := #[]
          for index in List.range structureInfo.fieldNames.size do
            let field := structureInfo.fieldNames[index]!
            let fieldLabel := contextualName env structureInfo.fieldNames field
            let fieldMeaning ← match structureInfo.getProjFn? index >>= env.find? with
              | some fieldInfo =>
                  let noun ← forallTelescopeReducing fieldInfo.type fun _ result =>
                    renderTypeNoun env structureInfo.fieldNames result
                  pure <| capitalize noun
              | none => pure "Description unavailable"
            rows := rows.push <| "| " ++ capitalize fieldLabel ++ " | " ++ fieldMeaning ++ " |"
          return "A state record used by the model.\n\n| Field | Meaning |\n| --- | --- |\n" ++
            String.intercalate "\n" rows.toList
      | none =>
          let cases := value.ctors.map fun constructor =>
            contextualName env value.ctors.toArray constructor
          return "The possible cases are:\n\n" ++ bullets cases
  | .thmInfo _ =>
      let claim := (splitOnce meaning (label ++ " proves that ")).map (·.2) |>.getD meaning
      let rendered := (renderStateClaim claim).getD (renderClaim claim)
      return "**Proof status:** Checked theorem\n\n" ++ rendered
  | .defnInfo _ | .opaqueInfo _ =>
      if let some transition := renderTransitionSystem label meaning then return transition
      if let some rule := renderRule label meaning then return rule
      if let some (_, value) := splitOnce meaning (label ++ " means ") then
        if let some table := renderRecordTable value "Value" then return table
      if let some applied := renderAppliedDefinition label meaning then return applied
      return capitalize (readableMeaning meaning)
  | _ => return capitalize (readableMeaning meaning)

private def declarationsByModule (env : Environment) (roots : Array Name) : Array (Name × Name × Array ConstantInfo) := Id.run do
  let mut groups : Array (Name × Name × Array ConstantInfo) := #[]
  for root in roots do
    for info in declarationsIn env root do
      let module := moduleFor env info.name
      match groups.findIdx? (fun entry => entry.2.1 == module) with
      | some index =>
          let entry := groups[index]!
          groups := groups.set! index (entry.1, entry.2.1, entry.2.2.push info)
      | none => groups := groups.push (root, module, #[info])
  groups.qsort fun left right => Name.quickLt left.2.1 right.2.1

private def renderFile (roots : Array Name) (env : Environment) (root module : Name)
    (declarations : Array ConstantInfo) : TermElabM (String × String) := do
  let moduleParts := nameParts module
  let sourcePath := modulePath module ".lean"
  let outputPath := modulePath module ".md"
  let sourceLink := repeatParent moduleParts.length ++ sourcePath
  let vocabularyLink := repeatParent (moduleParts.length - 1) ++ "vocabulary.md"
  let context := declarations.map (·.name)
  let mut sections := #[]
  for info in declarations do
    let references := semanticReferences roots env info
    let declarationContext := (context ++ references).push info.name
    let meaning ← renderDeclarationMarkdown roots env declarationContext info
    let heading := capitalize (contextualName env context info.name)
    sections := sections.push <| "## " ++ heading ++ "\n\n" ++ meaning
  let content := "# " ++ moduleTitle root module ++ "\n\n" ++
    "Formal source: [" ++ sourcePath ++ "](" ++ sourceLink ++ ") · " ++
    "[Vocabulary](" ++ vocabularyLink ++ ")\n\n" ++
    "**Audit status:** Complete · " ++ toString declarations.size ++ " formal object" ++
    (if declarations.size == 1 then "" else "s") ++ "\n\n" ++
    String.intercalate "\n\n" sections.toList ++ "\n"
  return (outputPath, content)

private def isProjectName (roots : Array Name) (name : Name) : Bool :=
  roots.any fun root => root.isPrefixOf name

private def vocabularyNames (roots : Array Name) (env : Environment)
    (groups : Array (Name × Name × Array ConstantInfo)) : Array Name := Id.run do
  let mut names : Array Name := #[]
  for group in groups do
    for info in group.2.2 do
      if isProjectName roots info.name && !isGeneratedName info.name && !names.contains info.name then
        names := names.push info.name
      if let .inductInfo inductiveInfo := info then
        if let some structureInfo := getStructureInfo? env inductiveInfo.name then
          for field in structureInfo.fieldNames do
            if !names.contains field then names := names.push field
        else
          for constructor in inductiveInfo.ctors do
            if !names.contains constructor then names := names.push constructor
      for reference in semanticReferences roots env info do
        if isProjectName roots reference && !isGeneratedName reference && !names.contains reference then
          names := names.push reference
  names.filter (fun name =>
    match env.find? name with
    | some (.thmInfo _) => false
    | some _ => true
    | none => false) |>.qsort Name.quickLt

private def termMeaning (roots : Array Name) (env : Environment) (context : Array Name)
    (name : Name) : TermElabM String := do
  match env.find? name with
  | none => return "Description unavailable: the declaration cannot be found."
  | some info =>
      match info with
      | .inductInfo value =>
          if let some structureInfo := getStructureInfo? env value.name then
            let fields := structureInfo.fieldNames.map fun field => contextualName env structureInfo.fieldNames field
            return "A record containing " ++ String.intercalate ", " fields.toList ++ "."
          return "A domain choice with cases " ++
            String.intercalate ", " (value.ctors.map fun ctor => contextualName env value.ctors.toArray ctor) ++ "."
      | .ctorInfo constructor =>
          return "A possible case of " ++ contextualName env context constructor.induct ++ "."
      | .thmInfo _ => return capitalize (← declarationMeaning roots env context info)
      | _ =>
          if env.isProjectionFn name then
            let noun ← forallTelescopeReducing info.type fun _ result => renderTypeNoun env context result
            return capitalize noun ++ " field of " ++ contextualName env context name.getPrefix ++ "."
          if ← returnsProp info.type then
            let label := contextualName env context name
            let meaning ← declarationMeaning roots env context info
            return (renderRule label meaning).getD <|
              (renderAppliedDefinition label meaning).getD (capitalize (readableMeaning meaning))
          let noun ← forallTelescopeReducing info.type fun _ result => renderTypeNoun env context result
          return capitalize noun ++ "."

private def renderVocabulary (roots : Array Name) (env : Environment)
    (groups : Array (Name × Name × Array ConstantInfo)) : TermElabM String := do
  let names := vocabularyNames roots env groups
  let mut entries := #[]
  for name in names do
    let label := capitalize (contextualName env names name)
    let meaning ← termMeaning roots env names name
    let module := moduleFor env name
    let sourcePath := modulePath module ".lean"
    entries := entries.push <| "## " ++ label ++ "\n\n" ++ meaning ++
      "\n\nDefined in [" ++ sourcePath ++ "](../" ++ sourcePath ++ ")."
  return "# Vocabulary\n\n" ++
    "Terms used across the generated formal specifications. Names are shortened only when their meaning remains unambiguous.\n\n" ++
    String.intercalate "\n\n" entries.toList ++ "\n"

private def renderIndex (groups : Array (Name × Name × Array ConstantInfo))
    (documents : Array (String × String)) : String :=
  let entries := groups.zip documents |>.map fun (group, document) =>
    let status := if document.2.contains "Description unavailable" then "Incomplete" else "Complete"
    let role := match (nameParts group.1).getLast? with
      | some "Spec" => "Specification"
      | some "Model" => "Model"
      | some "Proof" => "Proofs"
      | _ => "Formal"
    "| [" ++ moduleTitle group.1 group.2.1 ++ "](" ++ document.1 ++ ") | " ++
      role ++ " | " ++ toString group.2.2.size ++ " | " ++ status ++ " |"
  "# Formal specifications\n\n" ++
    "**Audit status:** " ++
      (if documents.any (·.2.contains "Description unavailable") then "Incomplete" else "Complete") ++
    "\n\n| Document | Role | Formal objects | Description |\n| --- | --- | ---: | --- |\n" ++
    String.intercalate "\n" entries.toList ++ "\n\n[Vocabulary](vocabulary.md)\n"

private def renderFiles (roots : Array Name) : TermElabM (List (String × String)) := do
  let env ← getEnv
  let groups := declarationsByModule env roots
  if groups.isEmpty then throwError "description roots contain no public declarations"
  let documents ← groups.mapM fun group => renderFile roots env group.1 group.2.1 group.2.2
  let vocabulary ← renderVocabulary roots env groups
  return (("index.md", renderIndex groups documents) ::
    ("vocabulary.md", vocabulary) :: documents.toList)

syntax "describeFiles% " ident,* : term

elab_rules : term
  | `(describeFiles% $roots:ident,*) => do
      let names := roots.getElems.map (·.getId)
      let files ← renderFiles names
      return Lean.toExpr files

end LibSpec.Description
