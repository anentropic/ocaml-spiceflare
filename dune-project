(lang dune 3.18)

(using melange 0.1)

(name spiceflare)

(version 4.20260317.1)

(generate_opam_files true)

(package
 (name spiceflare)
 (synopsis "Cloudflare Workers Melange binding generator")
 (description
  "Generates Melange external binding declarations for the Cloudflare Workers runtime API surface from @cloudflare/workers-types.")
 (depends
  (ocaml
   (>= 5.2))
  (yojson
   (>= 2.0))
  (alcotest
   (and
    :with-test
    (>= 1.7)))))
