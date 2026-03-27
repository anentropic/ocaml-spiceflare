(** Output AST for Melange binding declarations.

    This models the structure of the generated .ml files. It is independent
    of the input IR — the transform stage maps between them. *)

(** OCaml type expressions *)
type ocaml_type =
  | Tname of string  (** e.g., "string", "float", "t", "Kv.t" *)
  | Tapply of ocaml_type * ocaml_type list  (** e.g., string Js.Promise.t *)
  | Tvar of string  (** 'a, 'b *)
  | Toption of ocaml_type  (** T option *)
  | Tarray of ocaml_type  (** T array *)
  | Ttuple of ocaml_type list  (** T1 * T2 *)
  | Tunit  (** unit *)
  | Tarrow of arrow_param * ocaml_type  (** param -> return *)
  | Tobj  (** < .. > Js.t *)

and arrow_param = {
  ap_label : label;
  ap_type : ocaml_type;
  ap_mel_this : bool;  (** carries [@mel.this] *)
}

and label =
  | Nolabel
  | Labelled of string  (** ~name:type *)
  | Optional of string  (** ?name:type *)

(** Melange attributes *)
type mel_attr =
  | Mel_new
  | Mel_send
  | Mel_get
  | Mel_set
  | Mel_get_index
  | Mel_obj
  | Mel_module of string
  | Mel_variadic
  | Warning of string

(** An external declaration *)
type external_decl = {
  e_name : string;  (** OCaml name *)
  e_js_name : string;  (** JS string literal *)
  e_type : ocaml_type;  (** full arrow type *)
  e_attrs : mel_attr list;
  e_doc : string option;
}

(** Type declaration variants *)
type type_decl =
  | Abstract of { name : string; doc : string option }
  | Record of {
      name : string;
      fields : record_field list;
      doc : string option;
    }
  | Warning_type of { name : string; doc : string option }  (** [@@warning "-69"] *)

and record_field = {
  rf_name : string;
  rf_type : ocaml_type;
  rf_mel_as : string option;  (** [@mel.as "camelCase"] *)
  rf_optional : bool;
}

(** A Bind module for heterogeneous input unions *)
type bind_module = {
  bm_name : string;  (** e.g., "Bind" *)
  bm_constructors : (string * ocaml_type) list;  (** (name, input type) *)
  bm_has_null : bool;
}

(** Items that can appear in a generated module *)
type item =
  | Type of type_decl
  | External of external_decl
  | Bind of bind_module
  | Comment of string
  | Blank

(** A nested OCaml module within a generated file *)
type ocaml_module = {
  m_name : string;
  m_items : item list;
}

(** A complete generated .ml file *)
type output_file = {
  of_filename : string;  (** e.g., "kv.ml" *)
  of_header : string;  (** header comment *)
  of_modules : ocaml_module list;
  of_toplevel : item list;  (** top-level items not in a submodule *)
}
