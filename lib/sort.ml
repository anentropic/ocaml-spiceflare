(** Topological sort of declarations within a module group.

    Orders declarations so that type references point backward (to already-defined
    modules), which OCaml's sequential module system requires. Cycles are broken
    by emitting the first-visited cycle member first and logging a warning. *)

open Ir

module StringSet = Set.Make (String)
module StringMap = Map.Make (String)

(** Collect all type reference names from a type expression *)
let rec collect_type_refs acc (t : typ) =
  match t with
  | Ref { name; args } ->
    let acc = name :: acc in
    List.fold_left collect_type_refs acc args
  | Array elem -> collect_type_refs acc elem
  | Tuple elems | Union elems | Intersection elems ->
    List.fold_left collect_type_refs acc elems
  | Function { params; return_type } ->
    let acc =
      List.fold_left
        (fun a (p : param) -> collect_type_refs a p.p_type)
        acc params
    in
    collect_type_refs acc return_type
  | Object members -> collect_member_refs acc members
  | String_literal _ | Number_literal _ | Type_param _ -> acc

and collect_member_refs acc members =
  List.fold_left
    (fun a (m : member) ->
       match m with
       | Property { typ; _ } -> collect_type_refs a typ
       | Method { overloads; _ } ->
         List.fold_left
           (fun a (ov : method_overload) ->
              let a =
                List.fold_left
                  (fun a (p : param) -> collect_type_refs a p.p_type)
                  a ov.mo_params
              in
              collect_type_refs a ov.mo_return_type)
           a overloads)
    acc members

(** Collect all type reference names from a declaration *)
let collect_decl_refs (d : decl) =
  let acc = [] in
  let acc = collect_member_refs acc d.d_members in
  let acc = List.fold_left collect_type_refs acc d.d_extends in
  let acc = List.fold_left collect_type_refs acc d.d_implements in
  let acc =
    match d.d_type with
    | Some t -> collect_type_refs acc t
    | None -> acc
  in
  acc

(** Topologically sort declarations within a module group.
    Returns declarations ordered so that dependencies come first.
    Cycles are broken arbitrarily with a warning to stderr. *)
let sort_declarations (decls : decl list) : decl list =
  let local_names =
    List.fold_left
      (fun s d -> StringSet.add d.d_name s)
      StringSet.empty decls
  in
  let decl_map =
    List.fold_left
      (fun m d -> StringMap.add d.d_name d m)
      StringMap.empty decls
  in
  (* Build adjacency: d depends on refs that are in local_names *)
  let deps_of d =
    collect_decl_refs d
    |> List.filter (fun name ->
           StringSet.mem name local_names && name <> d.d_name)
    |> List.sort_uniq String.compare
  in
  (* DFS-based topological sort *)
  let visited = Hashtbl.create (List.length decls) in
  let in_stack = Hashtbl.create (List.length decls) in
  let result = ref [] in
  let rec visit name =
    if Hashtbl.mem visited name then ()
    else if Hashtbl.mem in_stack name then begin
      (* Cycle detected -- break it by treating as visited *)
      Printf.eprintf
        "Warning: cycle detected involving %s, breaking arbitrarily\n" name;
      Hashtbl.replace visited name true
    end
    else begin
      Hashtbl.replace in_stack name true;
      (match StringMap.find_opt name decl_map with
       | Some d ->
         List.iter visit (deps_of d);
         Hashtbl.replace visited name true;
         Hashtbl.remove in_stack name;
         result := d :: !result
       | None ->
         Hashtbl.replace visited name true;
         Hashtbl.remove in_stack name)
    end
  in
  List.iter (fun (d : decl) -> visit d.d_name) decls;
  List.rev !result
