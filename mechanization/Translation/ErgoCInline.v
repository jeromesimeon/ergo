(*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *)

Require Import String.
Require Import List.
Require Import Basics.

Require Import ErgoSpec.Backend.ErgoBackend.
Require Import ErgoSpec.Common.Utils.Result.
Require Import ErgoSpec.Common.Utils.Names.
Require Import ErgoSpec.Common.Utils.Provenance.
Require Import ErgoSpec.Common.Types.ErgoType.

Require Import ErgoSpec.Ergo.Lang.Ergo.
Require Import ErgoSpec.Ergo.Lang.ErgoMap.
Require Import ErgoSpec.ErgoC.Lang.ErgoC.
Require Import ErgoSpec.ErgoC.Lang.ErgoCStdlib.

Require Import ErgoSpec.Translation.ErgoCompContext.

Definition ergo_expr := Ergo.laergo_expr.
Definition ergo_stmt := Ergo.laergo_stmt.
Definition ergo_function := Ergo.laergo_function.
Definition ergo_clause := Ergo.laergo_clause.
Definition ergo_contract := Ergo.laergo_contract.
Definition ergo_declaration := Ergo.laergo_declaration.
Definition ergo_module := Ergo.laergo_module.

Section ErgoCInline.
  Context {bm:brand_model}.

  Definition ergo_map_expr_sane ctxt fn expr :=
    @ergo_map_expr provenance absolute_name compilation_context ctxt
                   (fun ctxt name expr => compilation_context_update_local_env ctxt name expr)
                   fn expr.

  Definition ergo_inline_foreach' (ctxt : compilation_context) (expr : ergo_expr) :=
    match expr with
    | EForeach prov rs whr fn =>
      (compose Some esuccess)
        (fold_right
           (fun rcd ker => (EUnaryOp prov OpFlatten) (EForeach prov (rcd::nil) whr ker))
           (match whr with
            | Some whr' => (EIf prov whr' (EArray prov (fn::nil)) (EArray prov nil))
            | None => (EArray prov (fn::nil))
            end)
           rs)
    | _ => None
    end.

  Definition ergo_inline_foreach ctxt := ergo_map_expr_sane ctxt ergo_inline_foreach'.

  Fixpoint ergo_letify_function'
           (prov : provenance)
           (body : ergo_expr)
           (args : list (string * option laergo_type * ergo_expr)) : ergo_expr :=
    match args with
    | nil => body
    | (n,t,v)::rest => ELet prov n t v (ergo_letify_function' prov body rest)
    end.

  Definition keep_param_types (params:list (string * laergo_type)) : list (string * option laergo_type) :=
    map (fun xy => (fst xy, Some (snd xy))) params.
  Definition discard_param_types (params:list (string * laergo_type)) : list (string * option laergo_type) :=
    map (fun xy => (fst xy, None)) params.
  
  Definition ergo_letify_function (prov : provenance) (fname:string) (fn : ergoc_function) (args : list ergo_expr) :=
    let fndesc :=
        match fn.(functionc_body) with
        | None =>
          match lookup String.string_dec ergoc_stdlib fname with
          | Some fn => esuccess (fn.(functionc_body), discard_param_types fn.(functionc_sig).(sigc_params))
          | None => built_in_function_not_found_error prov fname
          end
        | Some _ => esuccess (fn.(functionc_body), keep_param_types fn.(functionc_sig).(sigc_params))
        end
    in
    eolift
      (fun fndesc : option ergoc_expr * (list (string * option laergo_type)) =>
         let (fnbody, fnparams) := fndesc in
         match fnbody with
         | None => built_in_function_without_body_error prov fname
         | Some body =>
           match zip fnparams args with
           | Some args' =>
             esuccess (ergo_letify_function' (ProvFunc (loc_of_provenance prov) fname) body args')
           | None =>
             call_params_error prov fname
           end
         end) fndesc.

  Definition ergo_inline_functions' (ctxt : compilation_context) (expr : ergo_expr) :=
  match expr with
  | ECallFun prov fname args => Some
      match lookup String.string_dec ctxt.(compilation_context_function_env) fname with
      | Some fn => ergo_letify_function prov fname fn args
      | None => function_not_found_error prov fname
      end
  | ECallFunInGroup prov gname fname args => Some
      match lookup String.string_dec ctxt.(compilation_context_function_group_env) gname with
      | Some t =>
        match lookup String.string_dec t fname with
        | Some fn => ergo_letify_function prov fname fn args
        | None => function_not_found_error prov fname
        end
      | None => function_not_found_error prov fname
      end
  | _ => None
  end.
  Definition ergo_inline_functions ctxt := ergo_map_expr_sane ctxt ergo_inline_functions'.

  Definition ergo_inline_expr := ergo_inline_functions.

  Definition ergo_inline_globals'
           (ctxt : compilation_context)
           (expr : ergoc_expr) :=
    match expr with
    | EVar loc name => Some
      match lookup String.string_dec (ctxt.(compilation_context_local_env)) name with
      | Some _ => esuccess expr
      | None =>
        match lookup String.string_dec (ctxt.(compilation_context_global_env)) name with
        | Some val => esuccess val
        | None => esuccess expr
        end
      end
    | _ => None
    end.
  Definition ergo_inline_globals ctxt := ergo_map_expr_sane ctxt ergo_inline_globals'.

  Definition ergo_inline_function
             (ctxt : compilation_context)
             (fn : ergoc_function) : eresult ergoc_function :=
    match fn.(functionc_body) with
    | None => esuccess fn
    | Some expr =>
      match eolift (ergo_inline_expr ctxt) (ergo_inline_globals ctxt expr) with
      | Success _ _ new_body =>
        esuccess (mkFuncC fn.(functionc_annot)
                               fn.(functionc_sig)
                                    (Some new_body))
      | Failure _ _ f => efailure f
      end
    end.

  Definition ergoc_inline_clause
             (coname : string)
             (ctxt : compilation_context)
             (clause : string * ergoc_function)
    : eresult ((string * ergoc_function) * compilation_context) :=
    let (clname, fn) := clause in
    elift (fun x =>
             ((clname,x), compilation_context_update_function_group_env ctxt coname clname x))
          (ergo_inline_function ctxt fn).

  Definition ergo_inline_contract
             (coname:string)
             (ctxt : compilation_context)
             (contract : ergoc_contract)
    : eresult (ergoc_contract * compilation_context) :=
    let clauses :=
        elift_context_fold_left
          (ergoc_inline_clause coname)
          contract.(contractc_clauses)
          ctxt
    in
    elift
      (fun xy =>
         (mkContractC contract.(contractc_annot) (fst xy), snd xy))
      clauses.
      
  Definition ergoc_inline_declaration
             (ctxt : compilation_context)
             (decl : ergoc_declaration)
    : eresult (ergoc_declaration * compilation_context) :=
    match decl with
    | DCExpr prov expr =>
      elift (fun x => (DCExpr prov x, ctxt)) (ergo_inline_expr ctxt expr)
    | DCConstant prov name ta expr =>
      elift (fun x =>
               (DCConstant prov name ta x, compilation_context_update_global_env ctxt name x))
            (ergo_inline_expr ctxt expr)
    | DCFunc prov name fn =>
      elift (fun x =>
               (DCFunc prov name x, compilation_context_update_function_env ctxt name x))
            (ergo_inline_function ctxt fn)
    | DCContract prov name c =>
      elift (fun xy =>
               (DCContract prov name (fst xy), snd xy))
            (ergo_inline_contract name ctxt c)
    end.

  Definition ergoc_inline_declarations
             (ctxt : compilation_context)
             (decls : list ergoc_declaration)
    : eresult (list ergoc_declaration * compilation_context) :=
    elift_context_fold_left
      ergoc_inline_declaration
      decls
      ctxt.
      
  Definition ergoc_inline_module
             (ctxt : compilation_context)
             (mod : ergoc_module)
    : eresult (ergoc_module * compilation_context) :=
    elift
      (fun res : (list ergoc_declaration * compilation_context) =>
         (mkModuleC
            mod.(modulec_annot)
            mod.(modulec_namespace)
            (fst res),
          snd res))
      (ergoc_inline_declarations ctxt mod.(modulec_declarations)).

End ErgoCInline.
