open! Dune_engine
open! Stdune
open Import
open Memo.Build.O

let () = Inline_tests.linkme

type workspace =
  { contexts : Context.t list
  ; conf : Dune_load.conf
  ; env : Env.t
  }

type build_system =
  { workspace : workspace
  ; scontexts : Super_context.t Context_name.Map.t
  }

let package_install_file w pkg =
  match Package.Name.Map.find w.conf.packages pkg with
  | None -> Error ()
  | Some p ->
    let name = Package.name p in
    let dir = Package.dir p in
    Ok
      (Path.Source.relative dir
         (Utils.install_file ~package:name ~findlib_toolchain:None))

let setup_env ~capture_outputs =
  let env =
    let env =
      if
        (not capture_outputs)
        || not (Lazy.force Ansi_color.stderr_supports_color)
      then
        Env.initial
      else
        Colors.setup_env_for_colors Env.initial
    in
    Env.add env ~var:"INSIDE_DUNE" ~value:"1"
  in
  Memo.Run.Fdecl.set Global.env env;
  env

let scan_workspace ?workspace_file ?x ?(capture_outputs = true) ?profile
    ?instrument_with ~ancestor_vcs () =
  let env = setup_env ~capture_outputs in
  let conf = Dune_load.load ~ancestor_vcs in
  let () = Workspace.init ?x ?profile ?instrument_with ?workspace_file () in
  let+ contexts = Context.DB.all () in
  List.iter contexts ~f:(fun (ctx : Context.t) ->
      let open Pp.O in
      Log.info
        [ Pp.box ~indent:1
            (Pp.text "Dune context:" ++ Pp.cut ++ Dyn.pp (Context.to_dyn ctx))
        ]);
  { contexts; conf; env }

let init_build_system ?only_packages ~sandboxing_preference ?caching w =
  Build_system.reset ();
  let promote_source ?chmod ~src ~dst ctx =
    let conf = Artifact_substitution.conf_of_context ctx in
    let src = Path.build src in
    let dst = Path.source dst in
    Artifact_substitution.copy_file ?chmod ~src ~dst ~conf ()
  in
  Build_system.init ~sandboxing_preference ~promote_source
    ~contexts:(List.map ~f:Context.build_context w.contexts)
    ?caching ();
  List.iter w.contexts ~f:Context.init_configurator;
  let+ scontexts = Gen_rules.gen w.conf ~contexts:w.contexts ?only_packages in
  { workspace = w; scontexts }

let find_context_exn t ~name =
  match List.find t.contexts ~f:(fun c -> Context_name.equal c.name name) with
  | Some ctx -> ctx
  | None ->
    User_error.raise
      [ Pp.textf "Context %S not found!" (Context_name.to_string name) ]

let find_scontext_exn t ~name =
  match Context_name.Map.find t.scontexts name with
  | Some ctx -> ctx
  | None ->
    User_error.raise
      [ Pp.textf "Context %S not found!" (Context_name.to_string name) ]
