(** Name conversion: camelCase/PascalCase to snake_case, keyword escaping.

    Uses structural acronym detection — no hardcoded acronym list. Sequences
    of uppercase letters optionally followed by digits are treated as single
    units, so KV, D1, R2, AI, URL etc. are handled correctly and future CF
    service acronyms work without codegen changes. *)

let ocaml_keywords =
  let tbl = Hashtbl.create 64 in
  List.iter
    (fun kw -> Hashtbl.replace tbl kw true)
    [
      "and"; "as"; "assert"; "asr"; "begin"; "class"; "constraint"; "do";
      "done"; "downto"; "else"; "end"; "exception"; "external"; "false";
      "for"; "fun"; "function"; "functor"; "if"; "in"; "include"; "inherit";
      "initializer"; "land"; "lazy"; "let"; "lor"; "lsl"; "lsr"; "lxor";
      "match"; "method"; "mod"; "module"; "mutable"; "new"; "nonrec";
      "object"; "of"; "open"; "or"; "private"; "rec"; "sig"; "struct";
      "then"; "to"; "true"; "try"; "type"; "val"; "virtual"; "when"; "while";
      "with";
    ];
  tbl

(** Convert a camelCase or PascalCase identifier to snake_case.

    The algorithm inserts underscores at case transitions:
    - Before an uppercase letter that follows a lowercase letter or digit
    - Before the last letter of an uppercase run that is followed by lowercase
      (so "KVNamespace" → "KV_Namespace" → "kv_namespace", not "k_v_namespace")

    Digits attached to preceding uppercase letters stay grouped
    (so "D1Database" → "D1_Database" → "d1_database"). *)
let to_snake_case s =
  if String.length s = 0 then s
  else
    let buf = Buffer.create (String.length s + 8) in
    let len = String.length s in
    let is_upper c = c >= 'A' && c <= 'Z' in
    let is_lower c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') in
    for i = 0 to len - 1 do
      let c = s.[i] in
      if i > 0 then begin
        let prev = s.[i - 1] in
        if is_upper c && is_lower prev then
          (* aB → a_B *)
          Buffer.add_char buf '_'
        else if
          is_upper c && is_upper prev && i + 1 < len && is_lower s.[i + 1]
        then
          (* ABc → A_Bc — split before last char of uppercase run *)
          Buffer.add_char buf '_'
      end;
      Buffer.add_char buf (Char.lowercase_ascii c)
    done;
    Buffer.contents buf

(** Escape OCaml reserved keywords by appending an underscore. *)
let escape_keyword s =
  if Hashtbl.mem ocaml_keywords s then s ^ "_" else s

(** Convert a JS member name to an OCaml identifier.
    Applies snake_case conversion then keyword escaping. *)
let ocaml_name_of_member name = name |> to_snake_case |> escape_keyword

(** Convert a JS class/interface name to an OCaml module name.
    PascalCase stays PascalCase but with underscores at word boundaries. *)
let module_name_of name =
  let snake = to_snake_case name in
  (* Capitalize first letter of each _-separated word *)
  String.split_on_char '_' snake
  |> List.map String.capitalize_ascii
  |> String.concat "_"

(** Convert a JS class/interface name to a snake_case filename stem.
    "KVNamespace" → "kv_namespace" *)
let filename_of name = to_snake_case name
