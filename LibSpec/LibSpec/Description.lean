import Lean.DocString
import Lean.Elab.ElabRules
import Lean.Elab.Term
import Lean.PrettyPrinter
import Lean.ResolveName

/-!
  Deterministic, Lean-native descriptions of declarations.

  A description is a generated view of an existing declaration.  It is not a
  proposition and it does not claim that the declaration's docstring is a
  faithful natural-language rendering of its semantics.  The elaborator below
  deliberately uses the declaration's elaborated type and its registered
  docstring so that the generated view cannot silently describe a different
  declaration or an unelaborated source type.
-/

namespace LibSpec.Description

private def render (declName : Lean.Name) (docString type : String) : String :=
  let name := Lean.Name.toString declName
  "# " ++ name ++ "\n\n" ++
  docString.trimAscii.copy ++ "\n\n" ++
  "## Type\n\n```lean\n" ++ name ++ " : " ++ type ++ "\n```\n"

private def prettyType (type : Lean.Expr) : Lean.Elab.Term.TermElabM String := do
  let options := ({} : Lean.Options)
    |>.set `pp.all false
    |>.set `pp.maxSteps 100000
    |>.set `pp.explicit true
    |>.set `pp.fullNames true
    |>.set `pp.universes true
    |>.set `format.width 120
  let formatted ← Lean.withOptions (fun _ => options) <| Lean.Meta.ppExpr type
  return formatted.pretty 120

syntax "describeSpec% " ident : term

elab_rules : term
  | `(describeSpec% $decl:ident) => do
      let declName ← Lean.resolveGlobalConstNoOverload decl
      let info ← Lean.getConstInfo declName
      let some docString ← Lean.findSimpleDocString? (← Lean.getEnv) declName
        | throwErrorAt decl "declaration `{declName}` has no docstring"
      if docString.trimAscii.isEmpty then
        throwErrorAt decl "declaration `{declName}` has an empty docstring"
      let type ← prettyType info.type
      let markdown := render declName docString type
      Lean.Elab.Term.elabTerm (Lean.Syntax.mkStrLit markdown) (some (Lean.mkConst ``String))

end LibSpec.Description
