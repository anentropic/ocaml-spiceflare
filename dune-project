(lang dune 3.18)

(using melange 0.1)

(name spiceflare)

(version 4.20260317.1)

(generate_opam_files true)

(source
 (github paul-j-lucas/spiceflare))

(license ISC)

(authors "Paul J. Lucas")

(maintainers "Paul J. Lucas <paul@lucasmail.org>")

(documentation "https://paul-j-lucas.github.io/spiceflare/")

(package
 (name spiceflare)
 (synopsis
  "Melange bindings for the Cloudflare Workers runtime API")
 (description
  "Complete set of Melange OCaml external bindings for the Cloudflare Workers runtime API, auto-generated from @cloudflare/workers-types.")
 (depends
  (ocaml
   (>= 5.4))
  (melange
   (>= 6.0.1))
  (odoc :with-doc)))

(package
 (name spiceflare-codegen)
 (synopsis
  "Code generator for Cloudflare Workers Melange bindings")
 (description
  "Reads a JSON intermediate representation extracted from @cloudflare/workers-types and emits structured .ml files covering the full Workers API surface.")
 (depends
  (ocaml
   (>= 5.4))
  (yojson
   (>= 2.0))
  (alcotest
   (and
    :with-test
    (>= 1.7)))
  (odoc :with-doc)))
