(** Pretty-print Binding AST as .ml source files.

    Uses the Format module for readable output with proper line breaking. *)

open Binding_ast

let pp = Format.fprintf

(* ── Type printing ───────────────────────────────────────────────────── *)

(** Does this type need parentheses when used as a type argument? *)
let needs_parens = function
  | Tarrow _ | Ttuple _ -> true
  | _ -> false

let rec pp_type fmt (t : ocaml_type) =
  match t with
  | Tname s -> pp fmt "%s" s
  | Tapply (base, args) ->
    (match args with
     | [ arg ] ->
       if needs_parens arg then pp fmt "(%a) %a" pp_type arg pp_type base
       else pp fmt "%a %a" pp_type arg pp_type base
     | _ ->
       pp fmt "(%a) %a"
         (Format.pp_print_list
            ~pp_sep:(fun fmt () -> pp fmt ",@ ")
            pp_type)
         args pp_type base)
  | Tvar s -> pp fmt "%s" s
  | Toption inner ->
    if needs_parens inner then pp fmt "(%a) option" pp_type inner
    else pp fmt "%a option" pp_type inner
  | Tarray inner ->
    if needs_parens inner then pp fmt "(%a) array" pp_type inner
    else pp fmt "%a array" pp_type inner
  | Ttuple elems ->
    Format.pp_print_list
      ~pp_sep:(fun fmt () -> pp fmt " * ")
      (fun fmt t ->
         if needs_parens t then pp fmt "(%a)" pp_type t
         else pp_type fmt t)
      fmt elems
  | Tunit -> pp fmt "unit"
  | Tarrow (param, ret) -> pp_arrow_chain fmt param ret
  | Tobj -> pp fmt "< .. > Js.t"

and pp_arrow_chain fmt first_param ret =
  pp_arrow_param fmt first_param;
  pp fmt " ->@ ";
  match ret with
  | Tarrow (p, r) -> pp_arrow_chain fmt p r
  | _ -> pp_type fmt ret

and pp_arrow_param fmt { ap_label; ap_type; ap_mel_this } =
  if ap_mel_this then
    pp fmt "(%a%a[%@mel.this])" pp_label_prefix ap_label pp_type ap_type
  else
    match ap_label with
    | Nolabel -> pp_type fmt ap_type
    | Labelled name -> pp fmt "~%s:%a" name pp_type ap_type
    | Optional name -> pp fmt "?%s:%a" name pp_type ap_type

and pp_label_prefix fmt = function
  | Nolabel -> ()
  | Labelled name -> pp fmt "~%s:" name
  | Optional name -> pp fmt "?%s:" name

(* ── Attribute printing ──────────────────────────────────────────────── *)

let pp_mel_attr fmt = function
  | Mel_new -> pp fmt "[%@%@mel.new]"
  | Mel_send -> pp fmt "[%@%@mel.send]"
  | Mel_get -> pp fmt "[%@%@mel.get]"
  | Mel_set -> pp fmt "[%@%@mel.set]"
  | Mel_get_index -> pp fmt "[%@%@mel.get_index]"
  | Mel_obj -> pp fmt "[%@%@mel.obj]"
  | Mel_module m -> pp fmt "[%@%@mel.module %S]" m
  | Mel_variadic -> pp fmt "[%@%@mel.variadic]"
  | Warning w -> pp fmt "[%@%@warning %S]" w

let pp_attrs fmt attrs =
  List.iter (fun a -> pp fmt "@ %a" pp_mel_attr a) attrs

(* ── External declaration ────────────────────────────────────────────── *)

let pp_external fmt (e : external_decl) =
  (match e.e_doc with
   | Some doc -> pp fmt "(** %s *)@," doc
   | None -> ());
  pp fmt "@[<hv 2>external %s :@ %a@ = %S%a@]"
    e.e_name pp_type e.e_type e.e_js_name pp_attrs e.e_attrs

(* ── Record field ────────────────────────────────────────────────────── *)

let pp_record_field fmt (f : record_field) =
  let mel_as =
    match f.rf_mel_as with
    | Some s -> Printf.sprintf " [@@mel.as %S]" s
    | None -> ""
  in
  pp fmt "%s : %a%s;" f.rf_name pp_type f.rf_type mel_as

(* ── Type declaration ────────────────────────────────────────────────── *)

let pp_type_decl fmt = function
  | Abstract { name; doc } ->
    (match doc with
     | Some d -> pp fmt "(** %s *)@," d
     | None -> ());
    pp fmt "type %s" name
  | Alias { name; target; doc } ->
    (match doc with
     | Some d -> pp fmt "(** %s *)@," d
     | None -> ());
    pp fmt "type %s = %a" name pp_type target
  | Record { name; fields; doc } ->
    (match doc with
     | Some d -> pp fmt "(** %s *)@," d
     | None -> ());
    pp fmt "@[<v 2>type %s = {@ %a@]@,}"
      name
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> pp fmt "@ ")
         pp_record_field)
      fields
  | Warning_type { name; doc } ->
    (match doc with
     | Some d -> pp fmt "(** %s *)@," d
     | None -> ());
    pp fmt "type %s [%@%@warning \"-69\"]" name

(* ── Bind module ─────────────────────────────────────────────────────── *)

let pp_bind_module fmt (b : bind_module) =
  pp fmt "@[<v 0>module %s : sig@," b.bm_name;
  pp fmt "  type t@,";
  List.iter
    (fun (name, typ) ->
       pp fmt "  val %s : %a -> t@," name pp_type typ)
    b.bm_constructors;
  if b.bm_has_null then
    pp fmt "  val null : ('a -> t) -> 'a option -> t@,";
  pp fmt "end = struct@,";
  pp fmt "  type t@,";
  pp fmt "  external unsafe_cast : 'a -> t = \"%%identity\"@,";
  List.iter
    (fun (name, _typ) ->
       pp fmt "  let %s = unsafe_cast@," name)
    b.bm_constructors;
  if b.bm_has_null then begin
    pp fmt
      "  let null f x = x |> Option.map f |> Js.Null.fromOption |> \
       unsafe_cast@,"
  end;
  pp fmt "end@]"

(* ── Item ────────────────────────────────────────────────────────────── *)

let pp_item fmt = function
  | Type td -> pp_type_decl fmt td
  | External e -> pp_external fmt e
  | Bind b -> pp_bind_module fmt b
  | Comment s -> pp fmt "(* %s *)" s
  | Blank -> pp fmt ""

(* ── Module ──────────────────────────────────────────────────────────── *)

let pp_module fmt (m : ocaml_module) =
  pp fmt "@[<v 0>module %s = struct@," m.m_name;
  List.iter
    (fun item ->
       pp fmt "  @[<hv 0>%a@]@," pp_item item)
    m.m_items;
  pp fmt "end@]"

(* ── Output file ─────────────────────────────────────────────────────── *)

let pp_output_file fmt (f : output_file) =
  pp fmt "%s@,@," f.of_header;
  List.iter
    (fun m ->
       pp_module fmt m;
       pp fmt "@,@,")
    f.of_modules;
  List.iter
    (fun item ->
       pp fmt "@[<hv 0>%a@]@," pp_item item)
    f.of_toplevel

(** Write all output files to a directory. *)
let emit_all ~dir (files : output_file list) =
  List.iter
    (fun f ->
       let path = Filename.concat dir f.of_filename in
       let oc = open_out path in
       let fmt = Format.formatter_of_out_channel oc in
       Format.pp_set_margin fmt 90;
       pp fmt "@[<v 0>";
       pp_output_file fmt f;
       pp fmt "@]@.";
       close_out oc;
       Printf.printf "Wrote %s\n" path)
    files

(* ── Test file generation ──────────────────────────────────────────── *)

(** Generate a compile-checking test file for a binding output file.
    The test file references types and externals with explicit annotations
    to trigger Melange type-checking of cross-module references and
    external signatures. *)
let gen_test_content (f : output_file) : string =
  let buf = Buffer.create 1024 in
  let bprintf = Printf.bprintf in
  let module_name =
    (* Derive module name from filename: "streams.ml" -> "Streams" *)
    let stem = Filename.chop_extension f.of_filename in
    String.capitalize_ascii stem
  in
  bprintf buf "(* Generated compile-checking test for %s *)\n\n" f.of_filename;
  bprintf buf "open Cf_workers_bindings.%s\n\n" module_name;
  (* For each submodule, reference its type t and externals *)
  List.iter
    (fun (m : ocaml_module) ->
       let safe_prefix =
         String.lowercase_ascii m.m_name
         |> String.map (fun c ->
              if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_'
              then c
              else '_')
       in
       (* Verify type t is resolvable *)
       bprintf buf "(* Verify %s.t is resolvable *)\n" m.m_name;
       bprintf buf "type %s_t = %s.t\n\n" safe_prefix m.m_name;
       (* Verify each external's full signature is type-correct *)
       List.iter
         (fun item ->
            match item with
            | External { e_name; _ } ->
              bprintf buf "let _%s_%s = %s.%s\n"
                safe_prefix e_name m.m_name e_name
            | _ -> ())
         m.m_items;
       bprintf buf "\n")
    f.of_modules;
  Buffer.contents buf

(** Write test files alongside binding files, in a parallel directory. *)
let emit_tests ~dir (files : output_file list) =
  List.iter
    (fun f ->
       let test_filename =
         let stem = Filename.chop_extension f.of_filename in
         stem ^ "_test.ml"
       in
       let path = Filename.concat dir test_filename in
       let content = gen_test_content f in
       let oc = open_out path in
       output_string oc content;
       close_out oc;
       Printf.printf "Wrote test %s\n" path)
    files
