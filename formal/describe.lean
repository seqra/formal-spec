import LibSpec
import model.SKILL
import proof.Workflow
import spec.Workflow

namespace FormalSpec

def formalDescriptions : List (String × String) :=
  describeFiles% FormalSpec.Spec, FormalSpec.Model, FormalSpec.Proof

end FormalSpec

def main : IO Unit := do
  let outputRoot : System.FilePath := ".formal-spec"
  for generated in ["index.md", "vocabulary.md", "spec.md", "spec", "model", "proof"] do
    let path := outputRoot / generated
    if ← path.pathExists then
      if ← path.isDir then IO.FS.removeDirAll path else IO.FS.removeFile path
  let mut incomplete := false
  for (relative, content) in FormalSpec.formalDescriptions do
    let path := outputRoot / relative
    if let some parent := path.parent then IO.FS.createDirAll parent
    IO.FS.writeFile path content
    if content.contains "Description unavailable" then incomplete := true
  if incomplete then
    throw <| IO.userError "generated descriptions are incomplete"
  IO.println s!"Generated {FormalSpec.formalDescriptions.length} description files in {outputRoot}."
