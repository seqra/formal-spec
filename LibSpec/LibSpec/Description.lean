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

private def libraryLabel (name : Name) : String :=
  humanize ((nameParts name).getLast?.getD name.toString)

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

/-- A binder the author left anonymous carries a compiler-generated name. Naming it after its
type keeps the sentence readable instead of quoting an internal identifier. -/
private def isInternalName (name : Name) : Bool :=
  name.hasMacroScopes || (name.toString.splitOn "_hyg").length > 1 ||
    (name.toString.splitOn "._@").length > 1 || (name.toString.splitOn "✝").length > 1

private def withoutArticle (noun : String) : String :=
  if noun.startsWith "a " then (noun.drop 2).toString
  else if noun.startsWith "an " then (noun.drop 3).toString
  else noun

private def readableBinder (binder : Name) (noun : String) : Name :=
  if !isInternalName binder then binder else
  let trimmed :=
    if noun.startsWith "a " then (noun.drop 2).toString
    else if noun.startsWith "an " then (noun.drop 3).toString
    else noun
  Name.mkSimple (if trimmed.isEmpty then "value" else trimmed.replace " " "_")

/-- An argument that is itself a phrase needs grouping, or a reader cannot tell where one
argument ends and the next begins. -/
private def groupArgument (value : String) : String :=
  if (value.splitOn ", ").length > 1 || (value.splitOn " of ").length > 1 then
    "(" ++ value ++ ")"
  else value

/-- The arguments a reader sees: a type or instance argument is machinery, not meaning. -/
private def explicitArguments (function : Expr) (arguments : Array Expr) : MetaM (Array Expr) := do
  let info ← getFunInfoNArgs function arguments.size
  let mut kept : Array Expr := #[]
  for index in [0 : arguments.size] do
    if index < info.paramInfo.size then
      if info.paramInfo[index]!.binderInfo.isExplicit then kept := kept.push arguments[index]!
    else
      kept := kept.push arguments[index]!
  return kept

private partial def renderExpression (roots : Array Name) (env : Environment) (context : Array Name)
    (expression : Expr) : TermElabM (Option String) := do
  if let some value := expression.rawNatLit? then return some (toString value)
  if let some value ← getNatValue? expression then return some (toString value)
  match expression with
  | .lit (.natVal value) => return some (toString value)
  | .lit (.strVal value) => return some s!"“{value}”"
  | .fvar id =>
      let userName ← id.getUserName
      if isInternalName userName then
        let noun ← renderTypeNoun env context (← id.getType)
        let trimmed := withoutArticle noun
        return some (if trimmed.isEmpty then "the value" else trimmed)
      return some (humanize userName.toString)
  | .const name _ =>
      if name == ``True then return some "true"
      if name == ``False then return some "false"
      if isSemanticName roots name then return some (contextualName env context name)
      return none
  | .forallE binder domain body binderInfo => do
      let binder := readableBinder binder (← renderTypeNoun env context domain)
      withLocalDecl binder binderInfo domain fun localValue => do
        let renderedBody ← renderExpression roots env context (body.instantiate1 localValue)
        let some renderedBody := renderedBody | return none
        if binderInfo == .instImplicit then return some renderedBody
        if !body.hasLooseBVar 0 && (← isProp domain) then
          let some renderedDomain ← renderExpression roots env context domain | return none
          return some s!"if {renderedDomain}, then {renderedBody}"
        let binderLabel := humanize binder.toString
        let domainLabel ← renderTypeNoun env context domain
        match body.instantiate1 localValue with
        | .forallE _ membership rest _ =>
            if !rest.hasLooseBVar 0 then
              let (membershipName, membershipArgs) := membership.getAppFnArgs
              if membershipName == ``Membership.mem && membershipArgs.size >= 2 then
                if membershipArgs[membershipArgs.size - 1]! == localValue then
                  let some collection ←
                    renderExpression roots env context membershipArgs[membershipArgs.size - 2]!
                    | return some s!"for every {binderLabel}, {domainLabel}, {renderedBody}"
                  let some claim ← renderExpression roots env context rest
                    | return some s!"for every {binderLabel}, {domainLabel}, {renderedBody}"
                  return some s!"every {binderLabel} in {collection} is such that {claim}"
        | _ => pure ()
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
              -- A branch may be labelled by a constructor only when it actually binds that
              -- constructor's fields. A pattern such as `[first, second]` compiles to as many
              -- alternatives as `List` has constructors while matching neither of them, and
              -- labelling it by position would attribute a branch to the wrong case.
              let labelled := inductiveInfo.ctors.length == matcherInfo.numAlts &&
                (List.range matcherInfo.numAlts).all fun index =>
                  match env.find? (inductiveInfo.ctors[index]!) with
                  | some (.ctorInfo constructor) =>
                      -- an alternative binding nothing still takes one parameter
                      matcherInfo.altNumParams[index]? == some (max 1 constructor.numFields)
                  | _ => false
              let mut cases := []
              let alternativePosition := matcherInfo.getFirstAltPos
              for index in List.range matcherInfo.numAlts do
                if _alt : alternativePosition + index < arguments.size then
                  let branch := arguments[alternativePosition + index]
                  let some renderedBranch ← renderExpression roots env context branch | return none
                  if labelled then
                    let constructor := inductiveInfo.ctors[index]!
                    let constructorLabel := contextualName env inductiveInfo.ctors.toArray constructor
                    cases := cases ++ [s!"when {constructorLabel}, {renderedBranch}"]
                  else
                    cases := cases ++ [renderedBranch]
                else return none
              if labelled then return some <| String.intercalate "; " cases
              let some subject ← renderExpression roots env context discriminator | return none
              return some <|
                s!"depending on {groupArgument subject}, one of: " ++ String.intercalate "; " cases
      if name == ``Eq && arguments.size == 3 then
        let some left ← renderExpression roots env context arguments[1]! | return none
        let some right ← renderExpression roots env context arguments[2]! | return none
        if right == "nothing" then return some s!"{left} is empty"
        return some s!"{left} equals {right}"
      if name == ``And && arguments.size == 2 then
        let some left ← renderExpression roots env context arguments[0]! | return none
        let some right ← renderExpression roots env context arguments[1]! | return none
        return some s!"{left}, and {right}"
      if name == ``Or && arguments.size == 2 then
        let some left ← renderExpression roots env context arguments[0]! | return none
        let some right ← renderExpression roots env context arguments[1]! | return none
        if (left.splitOn ", ").length > 1 || (right.splitOn ", ").length > 1 then
          return some s!"{left}; or else {right}"
        return some s!"{left}, or {right}"
      if name == ``Iff && arguments.size == 2 then
        let some left ← renderExpression roots env context arguments[0]! | return none
        let some right ← renderExpression roots env context arguments[1]! | return none
        return some s!"{left} exactly when {right}"
      if name == ``Not && arguments.size == 1 then
        let some value ← renderExpression roots env context arguments[0]! | return none
        let parts := value.splitOn " is one of "
        if parts.length == 2 then
          return some s!"{parts[0]!} is not one of {parts[1]!}"
        return some s!"it is not the case that {value}"
      if name == ``Ne && arguments.size == 3 then
        let some left ← renderExpression roots env context arguments[1]! | return none
        let some right ← renderExpression roots env context arguments[2]! | return none
        if right == "nothing" then return some s!"{left} is not empty"
        return some s!"{left} does not equal {right}"
      if name == ``Option.some && arguments.size == 2 then
        return ← renderExpression roots env context arguments[1]!
      if name == ``Option.none then return some "no value"
      if (name == ``Option.orElse || name == ``Option.getD) && arguments.size >= 3 then
        let some preferred ← renderExpression roots env context arguments[arguments.size - 2]!
          | return none
        let some fallback ← renderExpression roots env context arguments[arguments.size - 1]!
          | return none
        return some s!"{groupArgument preferred}, or failing that {groupArgument fallback}"
      if name == ``List.nil then return some "nothing"
      if name == ``String.ofList && arguments.size >= 1 then
        let some value ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"the text of {groupArgument value}"
      if name == ``Char.ofNat && arguments.size == 1 then
        let some code ← getNatValue? arguments[0]! | return none
        if code == 10 then return some "a line break"
        if code == 9 then return some "a tab"
        if code == 13 then return some "a carriage return"
        if code == 32 then return some "a space"
        return some s!"the character “{Char.ofNat code}”"
      if name == `HAppend.hAppend && arguments.size >= 2 then
        let some left ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some right ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{groupArgument left} followed by {groupArgument right}"
      if (name == ``ite || name == ``dite) && arguments.size >= 5 then
        let some condition ← renderExpression roots env context arguments[1]! | return none
        let some yes ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some no ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"if {condition} then {yes}, and otherwise {no}"
      if name == ``List.cons && arguments.size >= 2 then
        let some head ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some tail ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        if tail == "nothing" then return some s!"just {head}"
        return some s!"{head} followed by {tail}"
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
      if name == ``Exists && arguments.size == 2 then
        match arguments[1]! with
        | .lam binder domain body binderInfo =>
            let rendered ← withLocalDecl binder binderInfo domain fun localValue => do
              let body ← renderExpression roots env context (body.instantiate1 localValue)
              let some body := body | return none
              let binderLabel := humanize binder.toString
              let domainLabel ← renderTypeNoun env context domain
              return some s!"there is {domainLabel} {binderLabel} for which {body}"
            return rendered
        | _ => return none
      if name == ``Membership.mem && arguments.size >= 2 then
        let some collection ← renderExpression roots env context arguments[arguments.size - 2]!
          | return none
        let some element ← renderExpression roots env context arguments[arguments.size - 1]!
          | return none
        return some s!"{element} is one of {collection}"
      if name == ``LE.le && arguments.size >= 2 then
        let some left ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some right ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{left} is at most {right}"
      if name == ``LT.lt && arguments.size >= 2 then
        let some left ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some right ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{left} is less than {right}"
      if name == ``GE.ge && arguments.size >= 2 then
        let some left ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some right ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{left} is at least {right}"
      if name == ``GT.gt && arguments.size >= 2 then
        let some left ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some right ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{left} is greater than {right}"
      if name == `HSub.hSub && arguments.size >= 2 then
        let some left ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some right ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{left} less {right}"
      if (name == ``List.length || name == ``String.length) && arguments.size >= 1 then
        let some value ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"the length of {groupArgument value}"
      if name == ``List.Nodup && arguments.size >= 1 then
        let some value ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{value} holds nothing twice"
      if name == ``List.Sublist && arguments.size >= 2 then
        let some left ← renderExpression roots env context arguments[arguments.size - 2]! | return none
        let some right ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"{left} is a subsequence of {right}"
      if name == ``String.toList && arguments.size >= 1 then
        let some value ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"the characters of {groupArgument value}"
      if name == ``List.map && arguments.size >= 2 then
        let some transform ← renderExpression roots env context arguments[arguments.size - 2]!
          | return none
        let some collection ← renderExpression roots env context arguments[arguments.size - 1]!
          | return none
        return some s!"the {transform} of each of {groupArgument collection}"
      if name == ``List.sum && arguments.size >= 1 then
        let some value ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"the total of {groupArgument value}"
      if name == ``Prod.fst && arguments.size >= 1 then
        let some value ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"the first part of {groupArgument value}"
      if name == ``Prod.snd && arguments.size >= 1 then
        let some value ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"the second part of {groupArgument value}"
      if name == ``List.head? && arguments.size >= 1 then
        let some value ← renderExpression roots env context arguments[arguments.size - 1]! | return none
        return some s!"the first entry of {groupArgument value}"
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
        let shown ← explicitArguments expression.getAppFn arguments
        let renderedArguments ← shown.filterMapM (renderExpression roots env context)
        let label := contextualName env context name
        if renderedArguments.isEmpty then return some label
        return some <| label ++ " of " ++
          String.intercalate ", " (renderedArguments.toList.map groupArgument)
      match expression.getAppFn with
      | .fvar id =>
          let functionLabel := humanize (← id.getUserName).toString
          let renderedArguments ← expression.getAppArgs.filterMapM (renderExpression roots env context)
          if renderedArguments.isEmpty then return some functionLabel
          return some <| functionLabel ++ " of " ++
            String.intercalate ", " (renderedArguments.toList.map groupArgument)
      | _ => pure ()
      if !isGeneratedName name && env.contains name then
        let shown ← explicitArguments expression.getAppFn arguments
        let renderedArguments ← shown.filterMapM (renderExpression roots env context)
        let label := libraryLabel name
        if renderedArguments.isEmpty then return some label
        return some <| label ++ " of " ++
          String.intercalate ", " (renderedArguments.toList.map groupArgument)
      return none
  | .lam binder domain body binderInfo => do
      let binder := readableBinder binder (← renderTypeNoun env context domain)
      withLocalDecl binder binderInfo domain fun localValue =>
        renderExpression roots env context (body.instantiate1 localValue)
  | .letE binder type value body _ =>
      withLetDecl binder type value fun localValue =>
        renderExpression roots env context (body.instantiate1 localValue)
  | .mdata _ body | .proj _ _ body => renderExpression roots env context body
  | _ => return none

/-- Whether the definition itself is a case analysis, rather than merely containing one somewhere
inside. A record whose fields happen to match on something is still a record. -/
private partial def bodyIsMatch (env : Environment) (value : Expr) : Bool :=
  match value with
  | .lam _ _ body _ => bodyIsMatch env body
  | .mdata _ body => bodyIsMatch env body
  | _ =>
      match value.getAppFn with
      | .const name _ => (getMatcherInfoCore? env name).isSome
      | _ => false

/-- Whether a definition's body is compiler-built recursion machinery rather than what the
author wrote. Such a body describes how the recursion is justified, not what the function means. -/
private def usesRecursionMachinery (value : Expr) : Bool :=
  value.getUsedConstants.any fun name =>
    let rendered := name.toString
    rendered.endsWith ".brecOn" || rendered.endsWith ".rec" || rendered.endsWith ".recOn" ||
      rendered.endsWith ".below" || rendered.startsWith "WellFounded."

/-- The cases an author wrote a recursive definition as, taken from its equations. -/
private def equationMeanings (roots : Array Name) (env : Environment) (context : Array Name)
    (name : Name) : TermElabM (Option (List String)) := do
  let some equations ← getEqnsFor? name | return none
  let mut rendered : List String := []
  for equation in equations do
    let some info := env.find? equation | return none
    let some line ← renderExpression roots env context info.type | return none
    rendered := rendered ++ [line]
  if rendered.isEmpty then return none
  return some rendered

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
            if (← whnf (← inferType value)).isSort then
              let noun ← renderTypeNoun env context value
              return s!"{label} means {noun}."
            if usesRecursionMachinery value || bodyIsMatch env value then
              match ← equationMeanings roots env context info.name with
              | some cases =>
                  return s!"{label} is given case by case: " ++
                    String.intercalate "; " cases ++ "."
              | none =>
                  -- Recursion machinery describes how a recursion is justified, never what the
                  -- definition means, so it is not offered to a reader in place of the cases.
                  if !usesRecursionMachinery value then
                    if let some meaning ← renderExpression roots env context value then
                      return s!"{label} means {meaning}."
                  let noun ← forallTelescopeReducing info.type fun _ result =>
                    renderTypeNoun env context result
                  return s!"{label} defines {noun}, case by case over its argument."
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

private def connectiveMarkers : List String :=
  [", and ", ", or ", ", then ", "if ", "for every ", "there is ",
    "it is not the case that ", " exactly when "]

private def carriesConnective (value : String) : Bool :=
  connectiveMarkers.any fun marker => (value.splitOn marker).length > 1

private def renderAppliedDefinition (label meaning : String) : Option String := do
  let body ← (splitOnce meaning (label ++ " means ")).map (·.2)
  if carriesConnective body || (body.splitOn "(").length > 1 then none else
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

/-- Splits a theorem's statement into what it ranges over, what it assumes, and what it
guarantees, by walking the statement itself. Recovering these by splitting rendered prose loses
the conclusion of a theorem that assumes nothing, because there is no phrase to split on. -/
private partial def theoremParts (roots : Array Name) (env : Environment) (context : Array Name)
    (type : Expr) (scope hypotheses : List String) :
    TermElabM (List String × List String × Option String) := do
  match type with
  | .forallE binder domain body binderInfo =>
      if binderInfo == .instImplicit then
        withLocalDecl binder binderInfo domain fun value =>
          theoremParts roots env context (body.instantiate1 value) scope hypotheses
      else if !body.hasLooseBVar 0 && (← isProp domain) then
        let rendered ← renderExpression roots env context domain
        let some assumption := rendered | return (scope, hypotheses, none)
        withLocalDecl binder binderInfo domain fun value =>
          theoremParts roots env context (body.instantiate1 value) scope
            (hypotheses ++ [assumption])
      else
        let noun ← renderTypeNoun env context domain
        let binder := readableBinder binder noun
        let entry := s!"{humanize binder.toString} — {noun}"
        withLocalDecl binder binderInfo domain fun value =>
          theoremParts roots env context (body.instantiate1 value) (scope ++ [entry]) hypotheses
  | _ =>
      let conclusion ← renderExpression roots env context type
      return (scope, hypotheses, conclusion)

private def renderTheoremParts (scope hypotheses : List String) (conclusion : String) : String :=
  let scopeSection :=
    if scope.isEmpty then "" else "**Scope**\n\n" ++ bullets scope ++ "\n\n"
  if hypotheses.isEmpty then
    scopeSection ++ "**Established**\n\n" ++ bullets (conjuncts conclusion)
  else
    scopeSection ++ "**Given**\n\n" ++ bullets hypotheses ++
      "\n\n**Guarantee**\n\n" ++ bullets (conjuncts conclusion)

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
      if let some stateClaim := renderStateClaim claim then
        return "**Proof status:** Checked theorem\n\n" ++ stateClaim
      match ← theoremParts roots env context info.type [] [] with
      | (scope, hypotheses, some conclusion) =>
          return "**Proof status:** Checked theorem\n\n" ++
            renderTheoremParts scope hypotheses conclusion
      | _ => return "**Proof status:** Checked theorem\n\n" ++ renderClaim claim
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
  let body := String.intercalate "\n\n" sections.toList
  let status := if body.contains "Description unavailable" then "Incomplete" else "Complete"
  let content := "# " ++ moduleTitle root module ++ "\n\n" ++
    "Formal source: [" ++ sourcePath ++ "](" ++ sourceLink ++ ") · " ++
    "[Vocabulary](" ++ vocabularyLink ++ ")\n\n" ++
    "**Audit status:** " ++ status ++ " · " ++ toString declarations.size ++ " formal object" ++
    (if declarations.size == 1 then "" else "s") ++ "\n\n" ++
    body ++ "\n"
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
