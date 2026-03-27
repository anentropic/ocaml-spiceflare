(** CLI entry point for the spiceflare binding generator.

    Usage: spiceflare <workers-ir.json> <output-dir> [test-dir] *)

let () =
  let argc = Array.length Sys.argv in
  if argc < 3 then begin
    Printf.eprintf "Usage: %s <workers-ir.json> <output-dir> [test-dir]\n" Sys.argv.(0);
    exit 1
  end;
  let ir_path = Sys.argv.(1) in
  let output_dir = Sys.argv.(2) in
  let test_dir =
    if argc >= 4 then Some Sys.argv.(3) else None
  in
  Printf.printf "Parsing %s...\n" ir_path;
  let ir = Spiceflare_lib.Ir_parse.parse_file ir_path in
  Printf.printf "Parsed %d module groups, version %s\n"
    (List.length ir.ir_modules) ir.ir_version;
  Printf.printf "Resolving type references...\n";
  let env = Spiceflare_lib.Resolve.resolve ir in
  Printf.printf "Transforming...\n";
  let files = Spiceflare_lib.Transform.transform_ir env ir in
  Printf.printf "Emitting %d files to %s/\n"
    (List.length files) output_dir;
  Spiceflare_lib.Emit.emit_all ~dir:output_dir files;
  (match test_dir with
   | Some td ->
     Printf.printf "Emitting test files to %s/\n" td;
     Spiceflare_lib.Emit.emit_tests ~dir:td files
   | None -> ());
  Printf.printf "Done.\n"
