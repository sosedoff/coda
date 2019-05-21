(**
 * [Parallel_scan] describes a signature of a solution for the following
 * problem statement:
 *
 * {e Efficiently compute a periodic scan on an infinite stream pumping at some
 * target rate, prefer maximizing throughput, then minimizing latency, then
 * minimizing size of state on an infinite core machine.}
 *
 * A periodic scan is a scan that only returns incremental results of some fold
 * every so often, and usually returns [None]. It requires a way to lift some
 * data ['d] into the space ['a] where an associative fold operation exists.
 *
 * The actual work of the scan is handled out-of-band, so here we expose an
 * interface of the intermediate state of some on-going long scan.
 *
 * Conceptually, you can imagine having a series of virtual trees where data
 * starts at the base and works its way up to the top, at which point we emit
 * the next incremental result. The implementation, for efficiency, does not
 * actually construct these trees, but {i succinctly} uses a ring buffer. The
 * state of the scan are these incomplete virtual trees.
 *
 * Specifically, the state of this scan is has the following primary operations:
 *
 * {!empty} to create the initial state
 *
 * {!update} adding raw data that will be lifted and processed later; adding 
 * merges for the completed raw/merged data. This moves us closer to emitting
 * something from a tree
 *
 * {!next_jobs} to get the next work to complete from this data
 *
 *)

open Core_kernel
open Coda_digestif

module Sequence_number : sig
  module Stable : sig
    module V1 : sig
      type t = int [@@deriving sexp, bin_io, version]
    end

    module Latest = V1
  end

  type t = Stable.Latest.t [@@deriving sexp]
end

(*Each node on the tree is viewed as a job that needs to be completed. When a job is completed, it creates a new "Todo" job and marks the old job as "Done"*)
module Job_status : sig
  module Stable : sig
    module V1 : sig
      type t = Todo | Done [@@deriving sexp, bin_io, version]
    end

    module Latest = V1
  end

  type t = Stable.Latest.t = Todo | Done [@@deriving sexp]
end

(*number of jobs that can be added to this tree. This number corresponding to a specific level of the tree. New jobs received is distributed across the tree based on this number. *)
module Weight : sig
  module Stable : sig
    module V1 : sig
      type t = int [@@deriving sexp, bin_io, version]
    end

    module Latest = V1
  end

  type t = Stable.Latest.t [@@deriving sexp]
end

(*Base Job: Proving new transactions*)
module Base : sig
  module Job : sig
    module Stable : sig
      module V1 : sig
        type 'd t =
          | Empty
          | Full of
              { job: 'd
              ; seq_no: Sequence_number.Stable.V1.t
              ; status: Job_status.Stable.V1.t }
        [@@deriving sexp, bin_io, version]
      end

      module Latest = V1
    end

    type 'd t = 'd Stable.Latest.t =
      | Empty
      | Full of
          { job: 'd
          ; seq_no: Sequence_number.Stable.V1.t
          ; status: Job_status.Stable.V1.t }
    [@@deriving sexp]
  end

  module Stable : sig
    module V1 : sig
      type 'd t = Weight.Stable.V1.t * 'd Job.Stable.V1.t
      [@@deriving sexp, bin_io, version]
    end

    module Latest = V1
  end

  type 'd t = 'd Stable.Latest.t [@@deriving sexp]
end

(* Merge Job: Merging two proofs*)
module Merge : sig
  module Job : sig
    module Stable : sig
      module V1 : sig
        type 'a t =
          | Empty
          | Part of 'a (*Only the left component of the job is available yet since we always complete the jobs from left to right*)
          | Full of
              { left: 'a
              ; right: 'a
              ; seq_no: Sequence_number.Stable.V1.t
                    (*Update number, for debugging*)
              ; status: Job_status.Stable.V1.t }
        [@@deriving sexp, bin_io, version]
      end

      module Latest = V1
    end

    type 'a t = 'a Stable.Latest.t =
      | Empty
      | Part of 'a
      | Full of
          { left: 'a
          ; right: 'a
          ; seq_no: Sequence_number.Stable.V1.t
          ; status: Job_status.Stable.V1.t }
    [@@deriving sexp]
  end

  module Stable : sig
    module V1 : sig
      type 'a t =
        (Weight.Stable.V1.t * Weight.Stable.V1.t) * 'a Job.Stable.V1.t
      [@@deriving sexp, bin_io, version]
    end

    module Latest = V1
  end

  type 'a t = 'a Stable.Latest.t [@@deriving sexp]
end

(** An available job is an incomplete job that has enough information for one
* to process it into a completed job *)
module Available_job : sig
  module Stable : sig
    module V1 : sig
      type ('a, 'd) t = Base of 'd | Merge of 'a * 'a [@@deriving sexp]
    end

    module Latest = V1
  end

  type ('a, 'd) t = ('a, 'd) Stable.Latest.t = Base of 'd | Merge of 'a * 'a
  [@@deriving sexp]
end

module Space_partition : sig
  module Stable : sig
    module V1 : sig
      type t = {first: int * int; second: (int * int) option}
      [@@deriving sexp, bin_io, version]
    end

    module Latest = V1
  end

  type t = Stable.Latest.t = {first: int * int; second: (int * int) option}
  [@@deriving sexp]
end

module Job_view : sig
  module Node : sig
    module Stable : sig
      module V1 : sig
        type 'a t = Base of 'a option | Merge of 'a option * 'a option
        [@@deriving sexp, bin_io, version]
      end

      module Latest = V1
    end

    type 'a t = 'a Stable.Latest.t =
      | Base of 'a option
      | Merge of 'a option * 'a option
    [@@deriving sexp]
  end

  module Stable : sig
    module V1 : sig
      type 'a t =
        { position: int
        ; seq_no: Sequence_number.Stable.V1.t
        ; status: Job_status.Stable.V1.t
        ; value: 'a Node.Stable.V1.t }
      [@@deriving sexp, bin_io, version]
    end

    module Latest = V1
  end

  type 'a t = 'a Stable.Latest.t [@@deriving sexp]
end

module State : sig
  (* bin_io, version omitted intentionally *)
  type ('a, 'd) t [@@deriving sexp]

  module Stable : sig
    module V1 : sig
      type nonrec ('a, 'd) t = ('a, 'd) t [@@deriving sexp, bin_io, version]
    end

    module Latest = V1
  end

  module Hash : sig
    type t = Digestif.SHA256.t
  end

  val hash : ('a, 'd) t -> ('a -> string) -> ('d -> string) -> Hash.t

  open Container

  module Make_foldable (M : Monad.S) : sig
    (** Effectfully fold chronologically. See {!fold_chronological} *)
    val fold_chronological_until :
         ('a, 'd) t
      -> init:'c
      -> fa:('c -> 'a Merge.t -> ('c, 'stop) Continue_or_stop.t M.t)
      -> fd:('c -> 'd Base.t -> ('c, 'stop) Continue_or_stop.t M.t)
      -> finish:('c -> 'stop M.t)
      -> 'stop M.t
  end
end

(** The initial state of the parallel scan at some parallelism *)
val empty : max_base_jobs:int -> delay:int -> ('a, 'd) State.t

(** Get the next k available jobs *)
val next_k_jobs :
  state:('a, 'd) State.t -> k:int -> ('a, 'd) Available_job.t list Or_error.t

(** Get all the available jobs *)
val all_jobs : ('a, 'd) State.t -> ('a, 'd) Available_job.t list list

(** Get all the available jobs to be done in the next update *)
val jobs_for_next_update :
  ('a, 'd) State.t -> ('a, 'd) Available_job.t list list

(** Compute how much data ['d] elements we are allowed to add to the state *)
val free_space : ('a, 'd) State.t -> int

(** Complete jobs needed at this state -- optionally emits the ['a] at the top
 * of the tree along with the ['d list] responsible for emitting the ['a]. *)
val update :
     data:'d list
  -> completed_jobs:'a list
  -> ('a, 'd) State.t
  -> (('a * 'd list) option * ('a, 'd) State.t) Or_error.t

(** The last ['a] we emitted from the top of the tree and the ['d list]
 * responsible for that ['a]. *)
val last_emitted_value : ('a, 'd) State.t -> ('a * 'd list) option

(** If there aren't enough slots for [max_slots] many ['d], then before
 * continuing onto the next virtual tree, split max_slots = (x,y) such that
 * x = number of slots till the end of the current tree and y = max_slots - x
 * (starts from the begining of the next tree)  *)
val partition_if_overflowing : ('a, 'd) State.t -> Space_partition.t

(** Do all the invariants of our parallel scan state hold; namely:
  * 1. The {!free_space} is equal to the number of empty leaves
  * 2. The empty leaves are in a contiguous chunk
  * 3. For all levels of the tree, if the start is empty, all is empty
  * 4. For all levels of the tree, at most one partial job is present
  * 5. All partial merge jobs are empty in the left side
  * 6. The tree is non-empty
  * 7. There exists non-zero free space (we're not deadlocked)
  *)
val is_valid : ('a, 'd) State.t -> bool

(** The base jobs ['d] that are pending and would be returned by available [Base]
 * jobs *)

(*val current_data : ('a, 'd) State.t -> 'd list*)

val current_job_sequence_number : ('a, 'd) State.t -> int

(*Get the current job sequence number *)

val view_jobs_with_position :
  ('a, 'd) State.t -> ('a -> 'c) -> ('d -> 'c) -> 'c Job_view.t list

(** All the base jobs that are part of the latest tree being filled 
 * i.e., does not include base jobs that are part of previous trees not 
 * promoted to the merge jobs yet*)
val base_jobs_on_latest_tree : ('a, 'd) State.t -> 'd list

(*returns true only if the position of the next 'd that could be enqueued is  
of the leftmost leaf of the tree*)
val next_on_new_tree : ('a, 'd) State.t -> bool

(*All the 'ds for which scan results are yet to computed*)
val pending_data : ('a, 'd) State.t -> 'd list
