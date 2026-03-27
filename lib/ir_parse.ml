(** Deserialize workers-ir.json into {!Ir.ir}.

    The JSON has explicit "kind" tags on every type node, so parsing is a
    clean match — no ambiguous field-presence discrimination needed. *)

open Ir

let ( let* ) = Result.bind

module J = Yojson.Safe.Util

(** Extract a string field, returning "" if absent *)
let str_field key json =
  match J.member key json with
  | `String s -> s
  | _ -> ""

(** Extract an optional string field *)
let str_opt key json =
  match J.member key json with
  | `String s -> Some s
  | _ -> None

(** Extract a bool field, defaulting to false *)
let bool_field key json =
  match J.member key json with
  | `Bool b -> b
  | _ -> false

(** Extract a list field, defaulting to empty *)
let list_field key json =
  match J.member key json with
  | `List l -> l
  | _ -> []

let rec parse_type (json : Yojson.Safe.t) : typ =
  match json with
  | `String s ->
    (* Shorthand: bare string means a simple named reference *)
    Ref { name = s; args = [] }
  | `Assoc _ ->
    let kind = str_field "kind" json in
    (match kind with
     | "ref" ->
       let name = str_field "name" json in
       let args = list_field "args" json |> List.map parse_type in
       Ref { name; args }
     | "array" ->
       let elem = J.member "elem" json |> parse_type in
       Array elem
     | "tuple" ->
       let elems = list_field "elements" json |> List.map parse_type in
       Tuple elems
     | "union" ->
       let members = list_field "members" json |> List.map parse_type in
       Union members
     | "intersection" ->
       let members = list_field "members" json |> List.map parse_type in
       Intersection members
     | "function" ->
       let params = list_field "params" json |> List.map parse_param in
       let return_type = J.member "return_type" json |> parse_type in
       Function { params; return_type }
     | "object" ->
       let members = list_field "members" json |> List.map parse_member in
       Object members
     | "string_literal" ->
       let value = str_field "value" json in
       String_literal value
     | "number_literal" ->
       let value =
         match J.member "value" json with
         | `Float f -> f
         | `Int i -> Float.of_int i
         | _ -> 0.0
       in
       Number_literal value
     | "type_param" ->
       let name = str_field "name" json in
       Type_param name
     | other ->
       (* Unknown type kind — treat as any *)
       Printf.eprintf "Warning: unknown type kind %S, treating as any\n" other;
       Ref { name = "any"; args = [] })
  | _ ->
    Ref { name = "any"; args = [] }

and parse_param json : param =
  {
    p_name = str_field "name" json;
    p_type = J.member "type" json |> parse_type;
    p_optional = bool_field "optional" json;
    p_rest = bool_field "rest" json;
  }

and parse_type_param_def json : type_param_def =
  {
    tp_name = str_field "name" json;
    tp_constraint =
      (match J.member "constraint" json with
       | `Null -> None
       | j -> Some (parse_type j));
    tp_default =
      (match J.member "default" json with
       | `Null -> None
       | j -> Some (parse_type j));
  }

and parse_member json : member =
  let kind = str_field "kind" json in
  let name = str_field "name" json in
  match kind with
  | "method" ->
    let overloads =
      list_field "overloads" json |> List.map parse_overload
    in
    Method
      {
        name;
        overloads;
        is_static = bool_field "static" json;
        doc = str_opt "doc" json;
      }
  | _ ->
    (* "property" or unknown — treat as property *)
    Property
      {
        name;
        typ = J.member "type" json |> parse_type;
        readonly = bool_field "readonly" json;
        optional = bool_field "optional" json;
        is_static = bool_field "static" json;
        doc = str_opt "doc" json;
      }

and parse_overload json : method_overload =
  {
    mo_type_params =
      list_field "type_params" json |> List.map parse_type_param_def;
    mo_params = list_field "params" json |> List.map parse_param;
    mo_return_type = J.member "return_type" json |> parse_type;
  }

let parse_decl_kind = function
  | "class" -> Class
  | "interface" -> Interface
  | "type_alias" -> Type_alias
  | "function" -> Function
  | "variable" -> Variable
  | other ->
    Printf.eprintf "Warning: unknown declaration kind %S\n" other;
    Interface

let parse_decl json : decl =
  {
    d_kind = str_field "kind" json |> parse_decl_kind;
    d_name = str_field "name" json;
    d_type_params =
      list_field "type_params" json |> List.map parse_type_param_def;
    d_members = list_field "members" json |> List.map parse_member;
    d_extends = list_field "extends" json |> List.map parse_type;
    d_implements = list_field "implements" json |> List.map parse_type;
    d_type =
      (match J.member "type" json with
       | `Null -> None
       | j -> Some (parse_type j));
    d_source_module = str_opt "source_module" json;
    d_doc = str_opt "doc" json;
  }

let parse_module_group json : module_group =
  {
    mg_name = str_field "name" json;
    mg_declarations =
      list_field "declarations" json |> List.map parse_decl;
  }

(** Parse a workers-ir.json file from disk. *)
let parse_file path : ir =
  let json = Yojson.Safe.from_file path in
  {
    ir_version = str_field "version" json;
    ir_modules = list_field "modules" json |> List.map parse_module_group;
  }

(** Parse from a JSON string (for testing). *)
let parse_string s : ir =
  let json = Yojson.Safe.from_string s in
  {
    ir_version = str_field "version" json;
    ir_modules = list_field "modules" json |> List.map parse_module_group;
  }
