From ITree Require Import
     ITree
     ITreeDefinition
     Interp.Traces.

From Coq Require Import
     Lists.List
     Arith.EqNat
     Arith.PeanoNat
     Program.Equality
     List.

(** * Modeling Concurrency with ITrees (CCS)

    We want to reason about concurrency with ITrees.

    For modeling concurrency, we use Milner's calculus of communicating systems(#)
    (CCS), a predecessor to π-calculus. In CCS, participating processes of a
    concurrent system have indivisible communications that can be composed in
    parallel.

    The primitive in the calculus is a _process_ that can have input and output
    _actions_ in which processes can communicate. Each action has a corresponding
    label, and can act as either an input or output (but not both).
    Processes can only communicate through complementary actions with the same
    label (i.e. same labels with actions of opposing polarity, such that process
    with input action `a` can communicate with a process with output action `a`).


    (#) Milner, R., Communication and Concurrency, 1989.
*)

Import ListNotations.
Set Implicit Arguments.

  (** CCS Operators:

      P := ∅          Empty Process
         | A = P1     Process Identifier *** (TODO)
         | a.P1       Action
         | P1 + P2    Choice (Sum type)
         | P1 ∥ P2    Parallel Composition
         | P1 ∖ a     Restriction *** (TODO)

      * Empty Process
      * Process Identifier: Identifier A refers to process P1. Allows
                            recursive definitions.
      * Action: Process P1 performs an action a. This could be a send or
                receive, depending on the polarity of the action a.
      * Choice : either P1 or P2 will be processed.
      * Parallel Composition: Processes P1 and P2 exist simultaneously
      * Restriction: Hides port a in process P1.
  *)


(** *Denotation of CCS with ITrees *)

Section ccs.

(* We need a decidable equality on labels for the Restriction and Parallel
   Composition operator. *)

Variable A : Type.
Variable A_dec_eq : forall x y: A, {x = y} + {x <> y}.
Variable A_beq : A -> A -> bool. (* Requires A to have a decidable equality *)

Variant Label : Type :=
| In (l : A) : Label
| Out (l : A) : Label.

Theorem label_dec_eq :
  forall x y : Label, {x = y} + {x <> y}.
Proof.
  decide equality.
Qed.

(* Denotation of CCS Operators as ITree events. *)
Variant ccsE : Type -> Type :=
| Or (n : nat): ccsE nat (* Note: choices are zero-indexed. *)
| Act : Label -> ccsE unit
| Sync : A -> ccsE unit
| Fail : ccsE void.

Definition ccs := itree ccsE unit.

(** Denotation of basic operations in CCS.
    For now, we reason about finitary ITrees. *)

(* The empty process. *)
Definition zero : ccs := Ret tt.

Definition fail : ccs := Vis Fail (fun x : void => match x with end).

(* Action operators, where l denotes the label. *)
Definition send (l : A) (k : ccs) : ccs := Vis (Act (In l)) (fun _ => k).

Definition recv (l : A) (k : ccs) : ccs := Vis (Act (Out l)) (fun _ => k).

(* Choose operator, where n is the number of choices. *)
Definition pick (n: nat) (k : nat -> ccs) : ccs := Vis (Or n) k.

(* Parallel composition operator (#).

   (#) Follows denotation of CCS parallel composition operator from
       Section 5 Rule IV. (p. 269) of:
       M. Henessy & G. Plotkin, A Term Model for CCS, 1980. *)
(* Invariant on atomic processes. *)
CoFixpoint par (p1 p2 : ccs) : ccs :=
  let par_left (p1 p2 : ccs) : ccs :=
  match p1, p2 with
  | (Vis (Act x) k), _ => Vis (Act x) (fun _ => par (k tt) p2)
  | Vis (Sync a) t1, _ => Vis (Sync a) (fun _ => par (t1 tt) p2)
  | Ret _, _ => p2
  | _, _ => fail
  end in
  let par_right (p1 p2 : ccs) : ccs :=
  match p1, p2 with
  | _, (Vis (Act x) k) => Vis (Act x) (fun _ => par p1 (k tt))
  | _, Vis (Sync a) t1 => Vis (Sync a) (fun _ => par p1 (t1 tt))
  | _, Ret _ => p1
  | _, _ => fail
  end in
  let par_comm (p1 p2 : ccs) : ccs :=
  match p1, p2 with
  | (Vis (Act (In l1)) k1), (Vis (Act (Out l2)) k2) =>
    if A_beq l1 l2 then Vis (Sync l1) (fun _ => par (k1 tt) (k2 tt)) else fail
  | (Vis (Act (Out l1)) k1), (Vis (Act (In l2)) k2) =>
    if A_beq l1 l2 then Vis (Sync l1) (fun _ => par (k1 tt) (k2 tt)) else fail
  | _, _ => fail
  end in
  match p1, p2 with
  | (Vis (Or n1) k1), (Vis (Or n2) k2) =>
      Vis (Or 3) (fun n0 : nat =>
        if beq_nat n0 0 then Vis (Or n1) (fun n11 : nat => par_left (k1 n11) p2)
        else if beq_nat n0 1 then Vis (Or n2) (fun n21 : nat => par_right p1 (k2 n21))
        else Vis (Or (n1 * n2))
                 (fun m => par_comm (k1 (m mod n2)) (k2 (m / n1))))
  | _, _ => fail
  end
.


(* To show correctness of our denotation of CCS, we compare
   the trace semantics between this denotation and the
   operational semantics for CCS. *)

(** *Operational Semantics for CCS *)

Section ccs_op.

Inductive ccs_o : Type :=
| Done : ccs_o
| Action : Label -> ccs_o -> ccs_o
| Choice : ccs_o -> ccs_o -> ccs_o
| Par : ccs_o -> ccs_o -> ccs_o
.

(* TODO Exercise : State invariant as a coinductive predicate,
and preservation by par. *)

(* TODO: Change to synchronous version of the LTS.
   obs := Sync (n).
   P -> (a ext) Q is not observed by the trace.
 *)
(* Transition rules for the Labelled Transition System. *)
Inductive step {l : A} : option Label -> ccs_o -> ccs_o -> Prop :=
| step_Send t :
    step (Some (In l)) (Action (In l) t) t
| step_Recv t :
    step (Some (Out l)) (Action (Out l) t) t
| step_Choice_L u v u' (A' : option Label) :
    step A' u u' -> step A' (Choice u v) u'
| step_Choice_R u v v' (A' : option Label) :
    step A' v v' -> step A' (Choice u v) v'
| step_Par_L u v u' (A' : option Label) :
    step A' u u' -> step A' (Par u v) (Par u' v)
| step_Par_R u v v' (A' : option Label) :
    step A' v v' -> step A' (Par u v) (Par u v')
| step_Par_Comm1 u v u' v' :
    step (Some (In l)) u u' -> step (Some (Out l)) v v' ->
    step None u' v'
| step_Par_Comm2 u v u' v' :
    step (Some (Out l)) u u' -> step (Some (In l)) v v' ->
    step None u' v'
.

(* Trace Semantics. *)

Inductive trace_ob : Type :=
| TNil : trace_ob
| TLabel : Label -> trace_ob -> trace_ob.

(* TODO *)
Inductive is_subtree_ob : ccs_o -> ccs_o -> Prop :=
| SubDone : is_subtree_ob Done Done.

Inductive is_trace_ob : ccs_o -> trace_ob -> Prop :=
| TraceDone :  is_trace_ob (Done) TNil
| TraceAction : forall A c tr, is_trace_ob (Action A c) (TLabel A tr)
| TraceChoice : forall c1 c2 sc1 sc2 tr,
    is_subtree_ob sc1 c1 -> is_subtree_ob sc2 c2 ->
    is_trace_ob sc1 tr -> is_trace_ob sc2 tr ->
    is_trace_ob (Choice c1 c2) tr
| TracePar : forall c1 c2 sc1 sc2 tr,
    is_subtree_ob sc1 c1 -> is_subtree_ob sc2 c2 ->
    is_trace_ob sc1 tr \/ is_trace_ob sc2 tr ->
    is_trace_ob (Par c1 c2) tr
.

End ccs_op.


(** *Equivalence on Traces

    We defined the trace semantics for our operational semantics above, and
    there is a trace semantics defined for ITrees (in theories.Interp.Traces).

    To show equivalence between these traces, we need to first show
    an equivalence relation between our varying notion of traces.
*)

Arguments trace _ _.
Inductive equiv_traces : trace_ob -> trace -> Prop :=
| TEqNil : equiv_traces TNil TEnd
| TEqRet : forall x, equiv_traces TNil (TRet x)
| TEqEvEnd : forall l,
    equiv_traces (TLabel l TNil) (TEventEnd (Act l))
| TEqEvResp : forall l tro trd,
    equiv_traces tro trd ->
    equiv_traces (TLabel l tro) (@TEventResponse ccsE unit unit (Act l) tt trd)
.

(* Now we can prove trace equivalence between the semantic models. *)
Theorem trace_eq_ob_den :
  (forall td trd, is_trace td trd -> exists to tro, is_trace_ob to tro /\ equiv_traces tro trd)
  /\ (forall to tro, is_trace_ob to tro -> exists td trd, is_trace td trd /\ equiv_traces tro trd).
Proof.
  split.
  - intros td trd H. induction H.
    + exists Done. exists TNil. repeat constructor.
    + exists Done. exists TNil. repeat constructor.
    + remember (observe t) as t'.
      exists
      * inversion H.
  - intros. admit.
Admitted.


(*-------------------- Notes -------------------------*)

(* Dec. 4, 2019. *)

(* OCaml's init operator. *)
Fixpoint init' {X : Type} acc (i n' : nat) (k : nat -> X) : list X :=
  match n' - i with
  | 0 => acc
  | S n =>  init' ((k i)::acc) (i+1) n k
  end.

Definition init {X : Type} (n : nat) (k : nat -> X) : list X :=
  init' [] (0) (n + 1) k.

(* Test *)
Eval cbv in init 2 (fun n => if beq_nat n 0 then 2 else 1).

(* Trace Equality. *)
(* Need this to be a CoFixpoint. *)
(*CoFixpoint trace_d (c: ccs) (acc : list Label) : set (list Label) :=
  match c with
  | Vis (Act A) k => trace_d (k tt) (A :: acc)
  | Vis (Or n) k =>
    fold_left (fun su1 c1 =>
                 set_union (list_eq_dec Label_dec_eq) su1
                           (trace_d c1 acc))
              (init n k) empty_set
  | Ret _ => set_add (list_eq_dec Label_dec_eq) acc empty_set
  | _ => empty_set
  end. *)

(* Nov. 26, 2019. *)
(* Example finitary ccs trees. *)

Inductive finitary : ccs -> Type :=
| ZeroFin : finitary zero
| SendFin (n : nat) (k : ccs): finitary (send n k)
| RecvFin (n : nat) (k : ccs) : finitary (recv n k)
| ChoiceFin (k : bool -> ccs) (finL: finitary (k true))
            (finR: finitary (k false)):
    finitary (pick k)
| TauFin (k : ccs) (finK: finitary k) : finitary (Tau k)
.
Example ccs1 (n : nat) : ccs := pick (fun _ => send n zero).

Example finite1 (n : nat) : Type := finitary (ccs1 n).

Eval cbv in finite1 1.

Example ccs2 (n : nat) : ccs := pick (fun b => if b
                                     then send n zero
                                     else recv n zero).

Example finite2 (n : nat) : Type := finitary (ccs2 1).

(* ✠ Question: Do we need finitary? Aren't all of these trees built from our
   operators going to be finite? *)

(* Helper function for choose --
   Crawling over possible labels in the ccs tree and flattening them as a list. *)
Program Fixpoint label_list (p : ccs) (D : finitary p) : list ccs := _.
Next Obligation.
  dependent induction D.
  - exact [].
  - exact [send n k].
  - exact [recv n k].
  - exact (List.app IHD1 IHD2).
  - exact IHD.
Defined.

(* Here is a convoluted attempt at going forward and trying to define the
   parallel composition operator... It is bad.*)
(* Wrong. *)
CoFixpoint choose1 (p1 p2 : list ccs) : bool -> ccs :=
  match p1 with
  | [] => match p2 with
         | [] => fun b => zero
         | h :: t => fun b => pick (choose [] t)
         end
  | h1 :: t1 => match p2 with
        | [] => fun b => zero
        | h2 :: t2 =>
          fun b =>
          match b with
          | true => pick (choose t1 p2)
          | false => pick (choose p1 t2)
          end
        end
  end.

(* Parallel composition operator. Wrong. *)
Definition par1 (p1 p2 : ccs) (pf1 : finitary p1) (pf2 : finitary p2) : ccs :=
  pick (choose (label_list pf1) (label_list pf2)).

(* These don't work because it doesn't reason about any of the labels in a
   meaningful way. It nests the choose operators, but in a totally non-
   sensical manner. We stare at the label lists again, to see how this is useful
   and what we could do. *)

(* Example label lists. *)

(* A ccs tree of depth 1. *)
Example label_list12 :=
  fun (n : nat) => label_list
                   (ChoiceFin (fun b => if b then send n zero
                                        else recv n zero)
                              (SendFin n zero)
                              (RecvFin n zero)).

Eval cbv in label_list12 1.
(* cbv is not the right reduction strategy, because we don't want it to unfold
   all the way. We need information about the polarity of labels. *)

(* A ccs tree of depth 2. *)
Example label_list2 :=
  fun (n1 n2 : nat) => label_list
                (ChoiceFin (fun b => if b then @send n1 zero
                                       else pick (fun _ => @send n2 zero))
                           (SendFin n1 zero)
                           (ChoiceFin (fun _ => @send n2 zero)
                                       (SendFin n2 zero)
                                       (SendFin n2 zero))).

Eval cbv in label_list2.


(* Woo! Our crawling operator is working as expected. Now, we think about
   how we can actually construct the parallel composition combinator.

   Let's start looking at an example to gain some intuition.
   What should the denotation of `(a.P + b.Q) ∥ (ā.∅ ∥ b̄.∅)` be? *)

(* Label lists of the components we're combining with the parallel combinator. *)
Example ex_label_list1 :=
  fun (n1 n2 : nat) (P Q : ccs) => label_list
                                (ChoiceFin (fun b => if b then @recv n1 P
                                                  else @recv n2 Q)
                                           (RecvFin n1 P)
                                           (RecvFin n2 Q)).

Eval cbv in ex_label_list1 1 2.

Example ex_label_list2 :=
  fun (n1 : nat) => label_list
                 (SendFin n1 zero).

Eval cbv in ex_label_list2 1.

Example ex_label_list3 :=
  fun (n2 : nat) => label_list
                 (SendFin n2 zero).

Eval cbv in ex_label_list3 2.

(* The possible transitions from `(a.P + b.Q) ∥ (ā.∅ ∥ b̄.∅)` are:
    1)  -(τ)⟶ P ∥ (∅ ∥ b̄.∅) -(b̄)⟶ P ∥ (∅ ∥ ∅)
    2)  -(τ)⟶ Q ∥ (ā.∅ ∥ ∅) -(ā)⟶ Q ∥ (∅ ∥ ∅) *)

(* ✠ Question: Does `∅ ∥ ∅` transition to anything?
   There are no applicable transition strategy in
   LTS (Labeled Transition System) for this agent expression. *)

(* Sub-example : (ā.∅ ∥ b̄.∅)
    1)  -(ā)⟶ (∅ ∥ b̄.∅) -(b̄)⟶ (∅ ∥ ∅)
    2)  -(b̄)⟶ (ā.∅ ∥ ∅) -(ā)⟶ (∅ ∥ ∅)
   This is an example where there are no complementary actions for a parallel
   composition.

   We can try defining a parallel composition operator with a straight-forward
   type declaration:
   > Definition par (p1 p2 : ccs) (pf1 : finitary p1) (pf2 : finitary p2): ccs.
   p1 := ā.∅
   p2 := b̄.∅
   par p1 p2 ≈ (āb̄, ∅ ∥ ∅) + (b̄ā, ∅ ∥ ∅)
             ≈ pick (fun b => if b then @send a (@send b ∅)
                                   else @send b (@send a ∅))
*)

