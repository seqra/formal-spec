# Inventory proof-first storyboard

<p align="center">
  <a href="../assets/demo.mp4"><img src="../assets/demo.gif" alt="Animation showing an inventory invariant, a proof-derived counterexample, and a corrected guard" width="960"></a>
</p>

The visual tells one five-minute story from product intent to retained
invariant:

| Frame | What appears | What it means |
| --- | --- | --- |
| **1 — Intent** | `reserved ≤ stock` | Reserved orders must remain fulfillable. |
| **2 — Green tests** | Two ordinary shipping cases pass. | The tested examples are correct, but incomplete. |
| **3 — Proof** | The model requires `reserved + quantity ≤ stock`. | The invariant chooses the boundary the implementation must respect. |
| **4 — Counterexample** | `stock = 5`, `reserved = 4`, `ship = 2` leaves `stock = 3`, `reserved = 4`. | Direct shipping consumes units already promised to reserved orders. |
| **5 — Correction** | Add the guard; all 126 declared cases agree. | The invariant and its boundary cases remain available for the next change. |

The symbolic theorem covers natural-number states and quantities under its
stated assumptions. The 126 generated cases are exhaustive for this declared
finite domain:

```text
stock     ∈ 0..5
reserved  ∈ 0..stock
quantity  ∈ 0..5
```

Finite cases give concrete feedback on the implementation; the symbolic proof
reasons over the broader modeled domain. Neither establishes behavior omitted
from the specification, and human review is still needed to judge that the
model represents the intended operation.
