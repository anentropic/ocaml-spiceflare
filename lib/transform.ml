(** Transform IR declarations into Melange binding AST.

    Applies all mapping rules from the design doc:
    - Primitive type mapping
    - Compound types (Promise, Array, unions, optionality)
    - Classes: abstract type + constructor + methods + properties
    - Interfaces: [@@mel.obj] for input, records for output
    - Union classification (nullable, finite input, fallback)
    - Overload disambiguation *)

open Ir
open Binding_ast

(* ── Helpers ─────────────────────────────────────────────────────────── *)

let unit_t = Tunit
let string_t = Tname "string"
let float_t = Tname "float"
let int_t = Tname "int"
let bool_t = Tname "bool"
let js_t a = Tapply (Tname "Js.t", [ a ])
let any_js_t = js_t (Tvar "'a")
let promise_t inner = Tapply (Tname "Js.Promise.t", [ inner ])

let make_arrow params ret =
  List.fold_right
    (fun p acc -> Tarrow (p, acc))
    params ret

let mel_this_param t =
  { ap_label = Nolabel; ap_type = t; ap_mel_this = true }

let labelled_param name t =
  { ap_label = Labelled name; ap_type = t; ap_mel_this = false }

let optional_param name t =
  { ap_label = Optional name; ap_type = t; ap_mel_this = false }

let positional_param t =
  { ap_label = Nolabel; ap_type = t; ap_mel_this = false }

(* ── Type mapping ────────────────────────────────────────────────────── *)

let rec map_type env ~current_module ~type_params (t : Ir.typ) : ocaml_type =
  match t with
  | Ref { name; args = [] }
    when List.exists (fun (tp : Ir.type_param_def) -> tp.tp_name = name) type_params ->
    Tvar ("'" ^ String.lowercase_ascii name)
  | Ref { name; args = [] } -> map_primitive_or_ref env ~current_module name
  | Ref { name = "Promise"; args = [ inner ] } ->
    promise_t (map_type env ~current_module ~type_params inner)
  | Ref { name = "ArrayBuffer"; args = _ } ->
    Tname "Js.TypedArray2.ArrayBuffer.t"
  | Ref { name = "Map"; args = [ k; v ] } ->
    Tapply (Tname "Js.Map.t", [ map_type env ~current_module ~type_params k; map_type env ~current_module ~type_params v ])
  | Ref { name = "Record"; args = [ _k; v ] } ->
    (* Record<string, T> → T Js.Dict.t *)
    Tapply (Tname "Js.Dict.t", [ map_type env ~current_module ~type_params v ])
  | Ref { name = "Partial"; args = [ inner ] } ->
    (* Partial<T> — just reference the type, optionality handled at member level *)
    map_type env ~current_module ~type_params inner
  | Ref { name = "Iterable" | "IterableIterator" | "AsyncIterableIterator";
          args = [ inner ] } ->
    (* Iterables → array for now *)
    Tarray (map_type env ~current_module ~type_params inner)
  | Ref { name; args } when Resolve.is_known_decl env name ->
    let cur_file_mod = String.capitalize_ascii current_module in
    let prefix =
      match Resolve.file_module_of env name with
      | Some m when m <> cur_file_mod -> m ^ "."
      | _ -> ""
    in
    let base = Tname (prefix ^ Naming.module_name_of name ^ ".t") in
    if args = [] then base
    else Tapply (base, List.map (map_type env ~current_module ~type_params) args)
  | Ref { name; args = _ } ->
    map_primitive_or_ref env ~current_module name
  | Array elem -> Tarray (map_type env ~current_module ~type_params elem)
  | Tuple elems -> Ttuple (List.map (map_type env ~current_module ~type_params) elems)
  | Union members -> map_union env ~current_module ~type_params members
  | Intersection members ->
    (* Intersection: use first type as approximation *)
    (match members with
     | [] -> any_js_t
     | first :: _ -> map_type env ~current_module ~type_params first)
  | Function { params; return_type } ->
    let ocaml_params =
      List.map
        (fun (p : Ir.param) ->
           let t = map_type env ~current_module ~type_params p.p_type in
           if p.p_optional then optional_param (Naming.ocaml_name_of_member p.p_name) t
           else labelled_param (Naming.ocaml_name_of_member p.p_name) t)
        params
    in
    make_arrow ocaml_params (map_type env ~current_module ~type_params return_type)
  | Object _members -> any_js_t  (* inline object literals → 'a Js.t *)
  | String_literal _ -> string_t
  | Number_literal _ -> float_t
  | Type_param name -> Tvar ("'" ^ String.lowercase_ascii name)

and map_primitive_or_ref env ~current_module name =
  match name with
  | "string" -> string_t
  | "number" | "double" | "float" -> float_t
  | "integer" | "int" -> int_t
  | "boolean" -> bool_t
  | "void" | "undefined" -> unit_t
  | "null" -> unit_t  (* standalone null — rare, handled in unions *)
  | "any" | "unknown" -> any_js_t
  | "never" -> Tvar "'a"
  | "object" -> Tobj
  | "Date" -> Tname "Js.Date.t"
  | "RegExp" -> Tname "Js.Re.t"
  | "Uint8Array" -> Tname "Js.TypedArray2.Uint8Array.t"
  | "Error" -> Tname "Js.Exn.t"
  | "Function" -> any_js_t
  | "Symbol" -> Tname "Js.Types.symbol"
  | _ ->
    if Resolve.is_known_decl env name then
      let cur_file_mod = String.capitalize_ascii current_module in
      let prefix =
        match Resolve.file_module_of env name with
        | Some m when m <> cur_file_mod -> m ^ "."
        | _ -> ""
      in
      Tname (prefix ^ Naming.module_name_of name ^ ".t")
    else
      (* Unknown type — emit as-is with a comment *)
      Tname name

(* ── Union classification ────────────────────────────────────────────── *)

and map_union env ~current_module ~type_params members =
  match classify_union members with
  | `Nullable inner -> Toption (map_type env ~current_module ~type_params inner)
  | `Fallback -> any_js_t

and classify_union members =
  let non_null =
    List.filter
      (fun m ->
         match m with
         | Ref { name = "null" | "undefined"; _ } -> false
         | _ -> true)
      members
  in
  if List.length non_null < List.length members then
    match non_null with
    | [ single ] -> `Nullable single
    | _ -> `Fallback
  else
    `Fallback

(* ── Method/property transforms ──────────────────────────────────────── *)

(** Transform an IR parameter to a binding arrow parameter *)
let transform_param env ~current_module ~type_params (p : Ir.param) : arrow_param =
  let t = map_type env ~current_module ~type_params p.p_type in
  if p.p_optional then
    optional_param (Naming.ocaml_name_of_member p.p_name) t
  else if p.p_rest then
    positional_param (Tarray t)
  else
    labelled_param (Naming.ocaml_name_of_member p.p_name) t

(** Build external decl for an instance method overload *)
let transform_method_overload env ~current_module ~type_params ~ocaml_name ~js_name ~self_type
    ~source_module ~is_static (ov : method_overload) ~has_rest : external_decl =
  let method_type_params = ov.mo_type_params @ type_params in
  let params =
    List.map (transform_param env ~current_module ~type_params:method_type_params) ov.mo_params
  in
  let return = map_type env ~current_module ~type_params:method_type_params ov.mo_return_type in
  let params, attrs =
    if is_static then
      (* Static methods: no receiver *)
      let attrs = [] in
      let attrs =
        match source_module with
        | Some m -> Mel_module m :: attrs
        | None -> attrs
      in
      (params, attrs)
    else
      (* Instance methods: receiver last with [@mel.this] *)
      let self = mel_this_param self_type in
      let attrs = [ Mel_send ] in
      let attrs =
        match source_module with
        | Some m -> Mel_module m :: attrs
        | None -> attrs
      in
      let attrs = if has_rest then Mel_variadic :: attrs else attrs in
      (params @ [ self ], attrs)
  in
  (* If no params (other than self), add unit *)
  let params =
    match params with
    | [ p ] when p.ap_mel_this -> [ positional_param Tunit; p ]
    | _ -> params
  in
  {
    e_name = ocaml_name;
    e_js_name = js_name;
    e_type = make_arrow params return;
    e_attrs = attrs;
    e_doc = None;
  }

(** Disambiguate overloaded method names *)
let disambiguate_overloads name overloads =
  if List.length overloads <= 1 then
    List.map (fun ov -> (Naming.ocaml_name_of_member name, ov)) overloads
  else
    List.mapi
      (fun i ov ->
         let suffix =
           if i = 0 then ""
           else "_" ^ string_of_int (i + 1)
         in
         (Naming.ocaml_name_of_member name ^ suffix, ov))
      overloads

(** Transform a member into external declarations *)
let transform_member env ~current_module ~type_params ~self_type ~source_module (m : Ir.member) : item list =
  match m with
  | Property { name; typ; readonly; is_static; doc; _ } ->
    let ocaml_name = Naming.ocaml_name_of_member name in
    let mapped_type = map_type env ~current_module ~type_params typ in
    let getter =
      if is_static then
        {
          e_name = ocaml_name;
          e_js_name = name;
          e_type = mapped_type;
          e_attrs =
            (match source_module with
             | Some m -> [ Mel_module m ]
             | None -> []);
          e_doc = doc;
        }
      else
        {
          e_name = ocaml_name;
          e_js_name = name;
          e_type =
            make_arrow [ mel_this_param self_type ] mapped_type;
          e_attrs =
            Mel_get
            :: (match source_module with
                | Some m -> [ Mel_module m ]
                | None -> []);
          e_doc = doc;
        }
    in
    let setter =
      if readonly || is_static then []
      else
        [
          External
            {
              e_name = "set_" ^ ocaml_name;
              e_js_name = name;
              e_type =
                make_arrow
                  [ positional_param mapped_type; mel_this_param self_type ]
                  unit_t;
              e_attrs =
                Mel_set
                :: (match source_module with
                    | Some m -> [ Mel_module m ]
                    | None -> []);
              e_doc = None;
            };
        ]
    in
    External getter :: setter
  | Method { name = "constructor"; _ } ->
    [] (* Constructors handled separately *)
  | Method { name; overloads; is_static; doc } ->
    let named_overloads = disambiguate_overloads name overloads in
    List.map
      (fun (ocaml_name, ov) ->
         let has_rest =
           List.exists (fun (p : Ir.param) -> p.p_rest) ov.mo_params
         in
         External
           (transform_method_overload env ~current_module ~type_params ~ocaml_name ~js_name:name
              ~self_type ~source_module ~is_static ov ~has_rest))
      named_overloads
    |> (fun items ->
          match items, doc with
          | (External e) :: rest, Some d ->
            External { e with e_doc = Some d } :: rest
          | _ -> items)

(* ── Constructor transform ───────────────────────────────────────────── *)

let find_constructor (members : Ir.member list) =
  List.find_map
    (fun m ->
       match m with
       | Method { name = "constructor"; overloads; _ } -> Some overloads
       | _ -> None)
    members

let transform_constructor env ~current_module ~type_params ~class_name ~source_module overloads : item list =
  let named = disambiguate_overloads "make" overloads in
  List.map
    (fun (ocaml_name, (ov : method_overload)) ->
       let method_type_params = ov.mo_type_params @ type_params in
       let params = List.map (transform_param env ~current_module ~type_params:method_type_params) ov.mo_params in
       let params =
         if params = [] then [ positional_param Tunit ] else params
       in
       let attrs =
         Mel_new
         :: (match source_module with
             | Some m -> [ Mel_module m ]
             | None -> [])
       in
       External
         {
           e_name = ocaml_name;
           e_js_name = class_name;
           e_type = make_arrow params (Tname "t");
           e_attrs = attrs;
           e_doc = None;
         })
    named

(* ── Class transform ─────────────────────────────────────────────────── *)

let transform_class env ~current_module (d : decl) : ocaml_module =
  let self_type = Tname "t" in
  let source_module = d.d_source_module in
  let type_params = d.d_type_params in
  let type_item = Type (Abstract { name = "t"; doc = d.d_doc }) in
  let constructor_items =
    match find_constructor d.d_members with
    | Some overloads ->
      transform_constructor env ~current_module ~type_params ~class_name:d.d_name ~source_module overloads
    | None -> []
  in
  let member_items =
    List.concat_map
      (transform_member env ~current_module ~type_params ~self_type ~source_module)
      d.d_members
  in
  {
    m_name = Naming.module_name_of d.d_name;
    m_items = [ type_item ] @ constructor_items @ member_items;
  }

(* ── Interface transform (input → mel.obj, output → record) ──────────── *)

let transform_interface_input env ~current_module (d : decl) : ocaml_module =
  (* [@@mel.obj] constructor with optional labeled args *)
  let type_params = d.d_type_params in
  let type_item =
    Type (Warning_type { name = "t"; doc = d.d_doc })
  in
  let params =
    List.filter_map
      (fun (m : Ir.member) ->
         match m with
         | Property { name; typ; optional; _ } ->
           let mapped = map_type env ~current_module ~type_params typ in
           let ocaml_name = Naming.ocaml_name_of_member name in
           if optional then Some (optional_param ocaml_name mapped)
           else Some (labelled_param ocaml_name mapped)
         | Method _ -> None)
      d.d_members
  in
  (* Add trailing unit for optional args *)
  let has_optional =
    List.exists
      (fun m ->
         match m with
         | Property { optional = true; _ } -> true
         | _ -> false)
      d.d_members
  in
  let params =
    if has_optional then params @ [ positional_param Tunit ]
    else params
  in
  let make_ext =
    External
      {
        e_name = "make";
        e_js_name = "";
        e_type = make_arrow params (Tname "t");
        e_attrs = [ Mel_obj ];
        e_doc = None;
      }
  in
  {
    m_name = Naming.module_name_of d.d_name;
    m_items = [ type_item; make_ext ];
  }

let transform_interface_output env ~current_module (d : decl) : ocaml_module =
  (* Plain OCaml record *)
  let type_params = d.d_type_params in
  let fields =
    List.filter_map
      (fun (m : Ir.member) ->
         match m with
         | Property { name; typ; optional; _ } ->
           let ocaml_name = Naming.ocaml_name_of_member name in
           let mapped = map_type env ~current_module ~type_params typ in
           let mapped = if optional then Toption mapped else mapped in
           let mel_as =
             if ocaml_name <> name then Some name else None
           in
           Some
             {
               rf_name = ocaml_name;
               rf_type = mapped;
               rf_mel_as = mel_as;
               rf_optional = optional;
             }
         | Method _ -> None)
      d.d_members
  in
  let type_item =
    Type
      (Record
         { name = "t"; fields; doc = d.d_doc })
  in
  (* Also emit method bindings if the interface has methods *)
  let method_items =
    List.concat_map
      (fun m ->
         match m with
         | Method _ ->
           transform_member env ~current_module ~type_params
             ~self_type:(Tname "t")
             ~source_module:d.d_source_module m
         | Property _ -> [])
      d.d_members
  in
  {
    m_name = Naming.module_name_of d.d_name;
    m_items = type_item :: method_items;
  }

let transform_interface env ~current_module (d : decl) : ocaml_module =
  if Resolve.is_input_interface env d.d_name then
    transform_interface_input env ~current_module d
  else
    transform_interface_output env ~current_module d

(* ── Type alias transform ────────────────────────────────────────────── *)

let transform_type_alias _env (d : decl) : ocaml_module =
  let type_item =
    match d.d_type with
    | Some (Union members) ->
      let all_string_literals =
        List.for_all
          (fun m -> match m with String_literal _ -> true | _ -> false)
          members
      in
      if all_string_literals then
        (* String enum — emit as abstract type with comment *)
        Type
          (Abstract
             {
               name = "t";
               doc =
                 Some
                   (Printf.sprintf "String enum: %s"
                      (String.concat " | "
                         (List.filter_map
                            (fun m ->
                               match m with
                               | String_literal s -> Some (Printf.sprintf "%S" s)
                               | _ -> None)
                            members)));
             })
      else
        Type (Abstract { name = "t"; doc = d.d_doc })
    | _ -> Type (Abstract { name = "t"; doc = d.d_doc })
  in
  { m_name = Naming.module_name_of d.d_name; m_items = [ type_item ] }

(* ── Global function / variable transform ────────────────────────────── *)

let transform_global_function env ~current_module (d : decl) : item list =
  let type_params = d.d_type_params in
  match d.d_type with
  | Some (Function { params; return_type }) ->
    let ocaml_params = List.map (transform_param env ~current_module ~type_params) params in
    let ocaml_params =
      if ocaml_params = [] then [ positional_param Tunit ]
      else ocaml_params
    in
    let return = map_type env ~current_module ~type_params return_type in
    let attrs =
      match d.d_source_module with
      | Some m -> [ Mel_module m ]
      | None -> []
    in
    [
      External
        {
          e_name = Naming.ocaml_name_of_member d.d_name;
          e_js_name = d.d_name;
          e_type = make_arrow ocaml_params return;
          e_attrs = attrs;
          e_doc = d.d_doc;
        };
    ]
  | _ -> []

let transform_global_variable env ~current_module (d : decl) : item list =
  let type_params = d.d_type_params in
  match d.d_type with
  | Some typ ->
    let attrs =
      match d.d_source_module with
      | Some m -> [ Mel_module m ]
      | None -> []
    in
    [
      External
        {
          e_name = Naming.ocaml_name_of_member d.d_name;
          e_js_name = d.d_name;
          e_type = map_type env ~current_module ~type_params typ;
          e_attrs = attrs;
          e_doc = d.d_doc;
        };
    ]
  | None -> []

(* ── Top-level: transform entire IR ──────────────────────────────────── *)

let transform_decl env ~current_module (d : decl) : ocaml_module option * item list =
  match d.d_kind with
  | Class -> (Some (transform_class env ~current_module d), [])
  | Interface -> (Some (transform_interface env ~current_module d), [])
  | Type_alias -> (Some (transform_type_alias env d), [])
  | Function -> (None, transform_global_function env ~current_module d)
  | Variable -> (None, transform_global_variable env ~current_module d)

let transform_module_group env (mg : Ir.module_group) : output_file =
  let modules = ref [] in
  let toplevel = ref [] in
  List.iter
    (fun d ->
       let mod_opt, items = transform_decl env ~current_module:mg.mg_name d in
       (match mod_opt with
        | Some m -> modules := m :: !modules
        | None -> ());
       toplevel := items @ !toplevel)
    mg.mg_declarations;
  {
    of_filename = mg.mg_name ^ ".ml";
    of_header =
      Printf.sprintf
        "(* Generated by spiceflare from @cloudflare/workers-types\n\
        \   Module: %s *)"
        mg.mg_name;
    of_modules = List.rev !modules;
    of_toplevel = List.rev !toplevel;
  }

(** Transform the full IR into output files. *)
let transform_ir env (ir : Ir.ir) : output_file list =
  List.map (transform_module_group env) ir.ir_modules
