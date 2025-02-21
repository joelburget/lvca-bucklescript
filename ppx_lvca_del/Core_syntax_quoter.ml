open Base
open Ppxlib
open Syntax_quoter
open Exp
open Lvca_del

module Binding_aware_pattern = struct
  let rec t ~loc = function
    | Lvca_syntax.Binding_aware_pattern.Operator (pos, name, scopes) ->
      let name_exp = string ~loc name in
      let scopes = scopes |> List.map ~f:(scope ~loc) |> list ~loc in
      [%expr
        Lvca_syntax.Binding_aware_pattern.Operator
          ([%e provenance ~loc pos], [%e name_exp], [%e scopes])]
    | Var (pos, str) ->
      [%expr
        Lvca_syntax.Binding_aware_pattern.Var
          ([%e provenance ~loc pos], [%e string ~loc str])]
    | Primitive p ->
      [%expr Lvca_syntax.Binding_aware_pattern.Primitive [%e Primitive.all ~loc p]]

  and scope ~loc (Lvca_syntax.Binding_aware_pattern.Scope (vars, body)) =
    let body = t ~loc body in
    let vars =
      vars
      |> List.map ~f:(fun (i, name) ->
             [%expr [%e provenance ~loc i], [%e string ~loc name]])
      |> list ~loc
    in
    [%expr Lvca_syntax.Binding_aware_pattern.Scope ([%e vars], [%e body])]
  ;;
end

let rec list_model ~loc = function
  | List_model.Nil i -> [%expr Lvca_del.List_model.Nil [%e provenance ~loc i]]
  | Cons (i, x, xs) ->
    [%expr
      Lvca_del.List_model.Cons ([%e provenance ~loc i], [%e x], [%e list_model ~loc xs])]
;;

module Pattern_model = struct
  let rec t ~loc = function
    | Pattern_model.Pattern.Operator (info, name, pats) ->
      let name_exp = Primitive.string ~loc name in
      let pats = pats |> List_model.map ~f:(t ~loc) |> list_model ~loc in
      [%expr
        Lvca_del.Pattern_model.Pattern.Operator
          ([%e provenance ~loc info], [%e name_exp], [%e pats])]
    | Var (info, str) ->
      [%expr
        Lvca_del.Pattern_model.Pattern.Var
          ([%e provenance ~loc info], [%e Primitive.string ~loc str])]
    | Primitive (info, p) ->
      [%expr
        Lvca_del.Pattern_model.Pattern.Primitive
          ([%e provenance ~loc info], [%e Primitive.all ~loc p])]
  ;;
end

module Core = struct
  let option ~loc = function
    | Option_model.Option.None i ->
      [%expr Lvca_del.Option_model.Option.None [%e provenance ~loc i]]
    | Some (i, a) ->
      [%expr Lvca_del.Option_model.Option.Some ([%e provenance ~loc i], [%e a])]
  ;;

  module Sort_model = struct
    let rec sort ~loc = function
      | Sort_model.Kernel.Sort.Name (i, str) ->
        [%expr
          Lvca_del.Sort_model.Kernel.Sort.Name
            ([%e provenance ~loc i], [%e Primitive.string ~loc str])]
      | Ap (i, str, lst) ->
        let lst = lst |> List_model.map ~f:(sort ~loc) |> list_model ~loc in
        [%expr
          Lvca_del.Sort_model.Kernel.Sort.Ap
            ([%e provenance ~loc i], [%e Primitive.string ~loc str], [%e lst])]
    ;;
  end

  module Ty = struct
    let rec t ~loc = function
      | Core.Type.Sort (info, s) ->
        [%expr
          Lvca_del.Core.Type.Sort ([%e provenance ~loc info], [%e Sort_model.sort ~loc s])]
      | Arrow (info, t1, t2) ->
        [%expr
          Lvca_del.Core.Type.Arrow
            ([%e provenance ~loc info], [%e t ~loc t1], [%e t ~loc t2])]
    ;;
  end

  let rec term ~loc = function
    | Core.Term_syntax.Term.Primitive (i, p) ->
      [%expr
        Lvca_del.Core.Term_syntax.Term.Primitive
          ([%e provenance ~loc i], [%e Primitive.all ~loc p])]
    | Operator (i, name, scopes) ->
      let scopes = scopes |> List_model.map ~f:(operator_scope ~loc) |> list_model ~loc in
      [%expr
        Lvca_del.Core.Term_syntax.Term.Operator
          ([%e provenance ~loc i], [%e Primitive.string ~loc name], [%e scopes])]
    | Ap (i, t1, t2) ->
      [%expr
        Lvca_del.Core.Term_syntax.Term.Ap
          ([%e provenance ~loc i], [%e term ~loc t1], [%e term ~loc t2])]
    | Case (i, tm, scopes) ->
      let scopes = scopes |> List_model.map ~f:(case_scope ~loc) |> list_model ~loc in
      [%expr
        Lvca_del.Core.Term_syntax.Term.Case
          ([%e provenance ~loc i], [%e term ~loc tm], [%e scopes])]
    | Lambda (i, ty, (var, body)) ->
      [%expr
        Lvca_del.Core.Term_syntax.Term.Lambda
          ( [%e provenance ~loc i]
          , [%e Ty.t ~loc ty]
          , ([%e single_var ~loc var], [%e term ~loc body]) )]
    | Let (i, tm, ty, (var, body)) ->
      let info = provenance ~loc i in
      let tm = term ~loc tm in
      let ty = ty |> Option_model.map ~f:(Ty.t ~loc) |> option ~loc in
      let var = single_var ~loc var in
      let body = term ~loc body in
      [%expr
        Lvca_del.Core.Term_syntax.Term.Let
          ([%e info], [%e tm], [%e ty], ([%e var], [%e body]))]
    | Let_rec (i, rows, (binders, body)) ->
      let info = provenance ~loc i in
      let rows = rows |> List_model.map ~f:(letrec_row ~loc) |> list_model ~loc in
      let binders = pattern ~loc binders in
      let body = term ~loc body in
      [%expr
        Lvca_del.Core.Term_syntax.Term.Let
          ([%e info], [%e rows], ([%e binders], [%e body]))]
    | Subst (i, (var, body), arg) ->
      let info = provenance ~loc i in
      let arg = term ~loc arg in
      let var = single_var ~loc var in
      let body = term ~loc body in
      [%expr
        Lvca_del.Core.Term_syntax.Term.Subst ([%e info], ([%e var], [%e body]), [%e arg])]
    | Term_var (i, name) ->
      [%expr
        Lvca_del.Core.Term_syntax.Term.Term_var
          ([%e provenance ~loc i], [%e string ~loc name])]
    | Quote (i, tm) ->
      [%expr
        Lvca_del.Core.Term_syntax.Term.Quote ([%e provenance ~loc i], [%e term ~loc tm])]
    | Unquote (i, tm) ->
      [%expr
        Lvca_del.Core.Term_syntax.Term.Quote ([%e provenance ~loc i], [%e term ~loc tm])]

  and case_scope ~loc (Core.Term_syntax.Case_scope.Case_scope (info, pat, tm)) =
    [%expr
      Lvca_del.Core.Term_syntax.Case_scope.Case_scope
        ( [%e provenance ~loc info]
        , [%e Binding_aware_pattern.t ~loc pat]
        , [%e term ~loc tm] )]

  and operator_scope
      ~loc
      (Core.Term_syntax.Operator_scope.Operator_scope (info, pats, tm))
    =
    let pats = pats |> List_model.map ~f:(Pattern_model.t ~loc) |> list_model ~loc in
    [%expr
      Lvca_del.Core.Term_syntax.Operator_scope.Operator_scope
        ([%e provenance ~loc info], [%e pats], [%e term ~loc tm])]

  and letrec_row ~loc (Core.Term_syntax.Letrec_row.Letrec_row (info, ty, tm)) =
    [%expr
      Lvca_del.Core.Term_syntax.Letrec_row.Letrec_row
        ([%e provenance ~loc info], [%e Ty.t ~loc ty], [%e term ~loc tm])]
  ;;
end
