open Base
module Format = Caml.Format
open Zanuda_core
open Zanuda_core.Utils

type input = Tast_iterator.iterator

let lint_id = "if_bool"
let group = LINT.Style
let level = LINT.Warn
let lint_source = LINT.FPCourse

let describe_itself () =
  describe_as_clippy_json
    lint_id
    ~group
    ~level
    ~docs:
      {|
### What it does?

Checks funny uses of boolean expressions, for example
* `if true ...`
* `if ... then false`
* `... && true`
* etc.

### Why it is important?

These unwise boolean expressions make code longer than it should be. For example, the expression `f x && false`
is semantically equivalent to false unless `f x` performs any effect (mutation, IO, exceptions, etc.).
The general rule of thumb is not to depend of the order of evaluation of this conjucts.
(The same idea as our functions should not depend on evaluation order of its' arguments.)
|}
;;

let msg ppf s = Caml.Format.fprintf ppf "%s\n%!" s

let report filename ~loc e =
  let module M = struct
    let txt ppf () = Utils.Report.txt ~filename ~loc ppf msg e

    let rdjsonl ppf () =
      RDJsonl.pp
        ppf
        ~filename:(Config.recover_filepath loc.loc_start.pos_fname)
        ~line:loc.loc_start.pos_lnum
        msg
        e
    ;;
  end
  in
  (module M : LINT.REPORTER)
;;

let run _ fallback =
  let pat =
    let open Tast_pattern in
    let ite =
      texp_ite ebool drop drop
      |> map1 ~f:(Format.asprintf "Executing 'if %b' smells bad")
      ||| (texp_ite drop ebool drop
          |> map1 ~f:(Format.asprintf "Executing 'if ... then %b' smells bad"))
      ||| (texp_ite drop drop (some ebool)
          |> map1 ~f:(Format.asprintf "Executing 'if ... then .. else %b' smells bad"))
    in
    let ops =
      texp_apply2 (texp_ident (path [ "Stdlib"; "&&" ])) ebool drop
      ||| texp_apply2 (texp_ident (path [ "Stdlib"; "&&" ])) drop ebool
      |> map1 ~f:(fun _ -> Format.asprintf "Conjunction with boolean smells smells bad")
    in
    ite ||| ops
  in
  let open Tast_iterator in
  { fallback with
    expr =
      (fun self expr ->
        let open Typedtree in
        let __ _ = Format.eprintf "%a\n%!" MyPrinttyped.expr expr in
        let loc = expr.exp_loc in
        Tast_pattern.parse
          pat
          loc
          ~on_error:(fun _desc () -> ())
          expr
          (fun s () ->
            CollectedLints.add
              ~loc
              (report loc.Location.loc_start.Lexing.pos_fname ~loc s))
          ();
        fallback.expr self expr)
  }
;;
