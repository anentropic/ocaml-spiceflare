(** Test suite for spiceflare binding generator. *)

(* ── Naming tests ────────────────────────────────────────────────────── *)

let test_snake_case () =
  let open Spiceflare_lib.Naming in
  let cases =
    [
      ("waitUntil", "wait_until");
      ("KVNamespace", "kv_namespace");
      ("D1Database", "d1_database");
      ("getURL", "get_url");
      ("toString", "to_string");
      ("readableStream", "readable_stream");
      ("R2Bucket", "r2_bucket");
      ("R2ObjectBody", "r2_object_body");
      ("WebSocket", "web_socket");
      ("HTMLRewriter", "html_rewriter");
      ("fetch", "fetch");
      ("x", "x");
      ("", "");
      ("ABCDef", "abc_def");
      ("AIGateway", "ai_gateway");
      ("name", "name");
      ("cacheStatus", "cache_status");
    ]
  in
  List.iter
    (fun (input, expected) ->
       Alcotest.(check string)
         (Printf.sprintf "to_snake_case %S" input)
         expected (to_snake_case input))
    cases

let test_keyword_escape () =
  let open Spiceflare_lib.Naming in
  let cases =
    [
      ("type", "type_");
      ("method", "method_");
      ("module", "module_");
      ("match", "match_");
      ("name", "name");  (* not a keyword *)
      ("open", "open_");
    ]
  in
  List.iter
    (fun (input, expected) ->
       Alcotest.(check string)
         (Printf.sprintf "escape_keyword %S" input)
         expected (escape_keyword input))
    cases

let test_ocaml_name_of_member () =
  let open Spiceflare_lib.Naming in
  let cases =
    [
      ("waitUntil", "wait_until");
      ("type", "type_");
      ("toString", "to_string");
    ]
  in
  List.iter
    (fun (input, expected) ->
       Alcotest.(check string)
         (Printf.sprintf "ocaml_name_of_member %S" input)
         expected (ocaml_name_of_member input))
    cases

let test_module_name () =
  let open Spiceflare_lib.Naming in
  let cases =
    [
      ("KVNamespace", "Kv_Namespace");
      ("Headers", "Headers");
      ("D1Database", "D1_Database");
      ("R2Bucket", "R2_Bucket");
    ]
  in
  List.iter
    (fun (input, expected) ->
       Alcotest.(check string)
         (Printf.sprintf "module_name_of %S" input)
         expected (module_name_of input))
    cases

(* ── IR parse tests ──────────────────────────────────────────────────── *)

let test_parse_minimal () =
  let json =
    {|{
      "version": "4.20260317.1",
      "modules": [
        {
          "name": "kv",
          "declarations": [
            {
              "kind": "interface",
              "name": "KVNamespace",
              "type_params": [],
              "members": [
                {
                  "kind": "method",
                  "name": "get",
                  "overloads": [
                    {
                      "type_params": [],
                      "params": [
                        {"name": "key", "type": {"kind": "ref", "name": "string", "args": []}, "optional": false, "rest": false}
                      ],
                      "return_type": {"kind": "ref", "name": "Promise", "args": [
                        {"kind": "union", "members": [
                          {"kind": "ref", "name": "string", "args": []},
                          {"kind": "ref", "name": "null", "args": []}
                        ]}
                      ]}
                    }
                  ],
                  "static": false
                },
                {
                  "kind": "property",
                  "name": "binding",
                  "type": {"kind": "ref", "name": "string", "args": []},
                  "readonly": true,
                  "optional": false,
                  "static": false
                }
              ],
              "extends": [],
              "implements": [],
              "source_module": null
            }
          ]
        },
        {
          "name": "globals",
          "declarations": [
            {
              "kind": "function",
              "name": "fetch",
              "type_params": [],
              "members": [],
              "extends": [],
              "implements": [],
              "type": {
                "kind": "function",
                "params": [
                  {"name": "input", "type": {"kind": "ref", "name": "string", "args": []}, "optional": false, "rest": false}
                ],
                "return_type": {"kind": "ref", "name": "Promise", "args": [
                  {"kind": "ref", "name": "Response", "args": []}
                ]}
              },
              "source_module": null
            }
          ]
        }
      ]
    }|}
  in
  let ir = Spiceflare_lib.Ir_parse.parse_string json in
  Alcotest.(check string) "version" "4.20260317.1" ir.ir_version;
  Alcotest.(check int) "module count" 2 (List.length ir.ir_modules);
  let kv = List.hd ir.ir_modules in
  Alcotest.(check string) "first module" "kv" kv.mg_name;
  Alcotest.(check int) "kv decl count" 1 (List.length kv.mg_declarations);
  let kv_ns = List.hd kv.mg_declarations in
  Alcotest.(check string) "kv ns name" "KVNamespace" kv_ns.d_name;
  Alcotest.(check int) "kv ns members" 2 (List.length kv_ns.d_members)

(* ── Emit tests ──────────────────────────────────────────────────────── *)

let emit_to_string f =
  let buf = Buffer.create 256 in
  let fmt = Format.formatter_of_buffer buf in
  Format.pp_set_margin fmt 90;
  f fmt;
  Format.pp_print_flush fmt ();
  Buffer.contents buf

let test_emit_external () =
  let open Spiceflare_lib.Binding_ast in
  let ext =
    {
      e_name = "get";
      e_js_name = "get";
      e_type =
        Tarrow
          ( { ap_label = Labelled "key"; ap_type = Tname "string"; ap_mel_this = false },
            Tarrow
              ( { ap_label = Nolabel; ap_type = Tname "t"; ap_mel_this = true },
                Tapply (Tname "Js.Promise.t", [ Toption (Tname "string") ]) ) );
      e_attrs = [ Mel_send ];
      e_doc = None;
    }
  in
  let result = emit_to_string (fun fmt -> Spiceflare_lib.Emit.pp_external fmt ext) in
  (* Check key fragments are present *)
  let contains haystack needle =
    let nlen = String.length needle in
    let hlen = String.length haystack in
    if nlen > hlen then false
    else
      let found = ref false in
      for i = 0 to hlen - nlen do
        if not !found && String.sub haystack i nlen = needle then found := true
      done;
      !found
  in
  Alcotest.(check bool) "contains external" true
    (String.length result > 0);
  Alcotest.(check bool) "contains mel.send" true
    (contains result "[@@mel.send]");
  Alcotest.(check bool) "contains mel.this" true
    (contains result "[@mel.this]")

(* ── Test runner ─────────────────────────────────────────────────────── *)

let () =
  Alcotest.run "spiceflare"
    [
      ( "naming",
        [
          Alcotest.test_case "to_snake_case" `Quick test_snake_case;
          Alcotest.test_case "escape_keyword" `Quick test_keyword_escape;
          Alcotest.test_case "ocaml_name_of_member" `Quick
            test_ocaml_name_of_member;
          Alcotest.test_case "module_name_of" `Quick test_module_name;
        ] );
      ( "ir_parse",
        [
          Alcotest.test_case "parse minimal" `Quick test_parse_minimal;
        ] );
      ( "emit",
        [
          Alcotest.test_case "emit external" `Quick test_emit_external;
        ] );
    ]
