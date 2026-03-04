import Mathlib.Tactic

-- A simple theorem with a sorry to fill
theorem add_comm_nat (n m : Nat) : n + m = m + n := by
  omega

-- A slightly harder one
theorem mul_add_distrib (a b c : Nat) : a * (b + c) = a * b + a * c := by
  ring

-- Something that needs search
theorem list_length_append (l₁ l₂ : List α) :
    (l₁ ++ l₂).length = l₁.length + l₂.length := by
  exact List.length_append ..
