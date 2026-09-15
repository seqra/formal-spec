import LibSpec

namespace DescriptionFixture.Model

namespace Left
def balance : Nat := 1
end Left

namespace Right
def balance : Nat := 2
end Right

def balancesDiffer : Prop := Left.balance ≠ Right.balance

@[describeAs "available inventory"]
def stock : Nat := 3

def files : List (String × String) := describeFiles% DescriptionFixture.Model

def report : String := String.intercalate "\n" (files.map Prod.snd)

example : report.contains "Left balance" := by native_decide
example : report.contains "Right balance" := by native_decide
example : report.contains "Available inventory" := by native_decide

end DescriptionFixture.Model
