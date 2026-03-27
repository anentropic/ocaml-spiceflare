(** Type reference resolution and input/output usage classification.

    Scans all declarations to determine which interfaces/classes appear in
    input (parameter) vs output (return/property) positions. This drives
    the decision between [@@mel.obj] constructors and plain OCaml records. *)

open Ir

type usage = Input | Output | Both | Unknown

type decl_info = {
  decl : decl;
  mutable usage : usage;
  module_name : string;  (** which output module this decl belongs to *)
}

type env = {
  decls : (string, decl_info) Hashtbl.t;
  (** All known declarations, keyed by name *)
}

(** Collect all named type references from a type expression *)
let rec collect_refs acc (t : typ) =
  match t with
  | Ref { name; args } ->
    let acc = name :: acc in
    List.fold_left collect_refs acc args
  | Array elem -> collect_refs acc elem
  | Tuple elems -> List.fold_left collect_refs acc elems
  | Union members -> List.fold_left collect_refs acc members
  | Intersection members -> List.fold_left collect_refs acc members
  | Function { params; return_type } ->
    let acc =
      List.fold_left (fun a p -> collect_refs a p.p_type) acc params
    in
    collect_refs acc return_type
  | Object members ->
    List.fold_left
      (fun a m ->
         match m with
         | Property { typ; _ } -> collect_refs a typ
         | Method { overloads; _ } ->
           List.fold_left
             (fun a ov ->
                let a =
                  List.fold_left
                    (fun a p -> collect_refs a p.p_type)
                    a ov.mo_params
                in
                collect_refs a ov.mo_return_type)
             a overloads)
      acc members
  | String_literal _ | Number_literal _ | Type_param _ -> acc

let mark_usage info new_usage =
  match info.usage, new_usage with
  | Unknown, u -> info.usage <- u
  | Input, Output | Output, Input -> info.usage <- Both
  | _ -> ()

(** Pass 1: Mark types appearing in parameter positions as Input.
    Pass 2: Mark types appearing in return/property positions as Output. *)
let classify_usage env (modules : module_group list) =
  let mark_refs position names =
    List.iter
      (fun name ->
         match Hashtbl.find_opt env.decls name with
         | Some info -> mark_usage info position
         | None -> ())
      names
  in
  List.iter
    (fun mg ->
       List.iter
         (fun (d : decl) ->
            List.iter
              (fun (m : member) ->
                 match m with
                 | Property { typ; _ } ->
                   mark_refs Output (collect_refs [] typ)
                 | Method { overloads; _ } ->
                   List.iter
                     (fun (ov : method_overload) ->
                        (* Params are input position *)
                        List.iter
                          (fun (p : param) ->
                             mark_refs Input (collect_refs [] p.p_type))
                          ov.mo_params;
                        (* Return is output position *)
                        mark_refs Output
                          (collect_refs [] ov.mo_return_type))
                     overloads)
              d.d_members)
         mg.mg_declarations)
    modules

(** Build the resolution environment from the full IR. *)
let resolve (ir : Ir.ir) : env =
  let env = { decls = Hashtbl.create 256 } in
  (* Register all declarations *)
  List.iter
    (fun (mg : module_group) ->
       List.iter
         (fun (d : decl) ->
            Hashtbl.replace env.decls d.d_name
              { decl = d; usage = Unknown; module_name = mg.mg_name })
         mg.mg_declarations)
    ir.ir_modules;
  (* Classify usage *)
  classify_usage env ir.ir_modules;
  env

(** Look up a declaration by name *)
let find_decl env name = Hashtbl.find_opt env.decls name

(** Check if a type name refers to a known declaration *)
let is_known_decl env name = Hashtbl.mem env.decls name

(** Get the file-level dune module name for a declaration.
    Uses String.capitalize_ascii (NOT Naming.module_name_of) because dune
    derives module names by capitalizing only the first letter of the filename stem.
    E.g., "workers_types" -> "Workers_types", NOT "Workers_Types". *)
let file_module_of env name =
  match Hashtbl.find_opt env.decls name with
  | Some info -> Some (String.capitalize_ascii info.module_name)
  | None -> None

(** Get usage classification for a declaration *)
let get_usage env name =
  match Hashtbl.find_opt env.decls name with
  | Some info -> info.usage
  | None -> Unknown

(** Determine if an interface should be emitted as [@@mel.obj] (input)
    or as a plain record (output). *)
let is_input_interface env name =
  match get_usage env name with
  | Input | Both -> true
  | Output | Unknown -> false
