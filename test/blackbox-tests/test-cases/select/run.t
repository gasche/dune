  $ $JBUILDER runtest -j1 --display short --root .
      ocamldep bar.ml.d
      ocamldep bar_no_unix.ml.d
      ocamldep bar_unix.ml.d
      ocamldep foo.ml.d
      ocamldep foo_fake.ml.d
      ocamldep foo_no_fake.ml.d
      ocamldep main.ml.d
        ocamlc .main.eobjs/bar.{cmi,cmo,cmt}
        ocamlc .main.eobjs/foo.{cmi,cmo,cmt}
      ocamlopt .main.eobjs/bar.{cmx,o}
      ocamlopt .main.eobjs/foo.{cmx,o}
        ocamlc .main.eobjs/main.{cmi,cmo,cmt}
      ocamlopt .main.eobjs/main.{cmx,o}
      ocamlopt main.exe
          main alias runtest
  bar has unix
  foo has no fake
