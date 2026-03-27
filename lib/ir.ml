(** Input AST types mirroring our custom workers-ir.json schema.

    The JSON IR is produced by the TypeScript extraction script (extract/)
    from @cloudflare/workers-types index.d.ts. These types are a 1:1
    structural match — no interpretation or transformation happens here. *)

(** Type descriptors — 10 variants covering the TypeScript type system subset
    relevant to Cloudflare Workers declarations. *)
type typ =
  | Ref of { name : string; args : typ list }
  | Array of typ
  | Tuple of typ list
  | Union of typ list
  | Intersection of typ list
  | Function of { params : param list; return_type : typ }
  | Object of member list
  | String_literal of string
  | Number_literal of float
  | Type_param of string

and param = {
  p_name : string;
  p_type : typ;
  p_optional : bool;
  p_rest : bool;
}

and type_param_def = {
  tp_name : string;
  tp_constraint : typ option;
  tp_default : typ option;
}

and member =
  | Property of {
      name : string;
      typ : typ;
      readonly : bool;
      optional : bool;
      is_static : bool;
      doc : string option;
    }
  | Method of {
      name : string;
      overloads : method_overload list;
      is_static : bool;
      doc : string option;
    }

and method_overload = {
  mo_type_params : type_param_def list;
  mo_params : param list;
  mo_return_type : typ;
}

(** Top-level declaration kinds *)
type decl_kind = Class | Interface | Type_alias | Function | Variable

(** A single declaration in the IR *)
type decl = {
  d_kind : decl_kind;
  d_name : string;
  d_type_params : type_param_def list;
  d_members : member list;
  d_extends : typ list;
  d_implements : typ list;
  d_type : typ option;  (** For Type_alias, Function, Variable *)
  d_source_module : string option;  (** null for globals, module specifier otherwise *)
  d_doc : string option;
}

(** A logical module group in the IR *)
type module_group = {
  mg_name : string;  (** e.g., "kv", "d1", "globals" *)
  mg_declarations : decl list;
}

(** The complete IR *)
type ir = {
  ir_version : string;
  ir_modules : module_group list;
}
