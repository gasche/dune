open! Dune_engine
open Stdune
open Action_builder.O
open Dep_conf

let make_alias expander s =
  let loc = String_with_vars.loc s in
  Expander.Or_exn.expand_path expander s
  |> Result.map ~f:(Alias.of_user_written_path ~loc)

let fold_source_dirs dir ~init ~f =
  let prefix_with, dir = Path.extract_build_context_dir_exn dir in
  match File_tree.find_dir dir with
  | None -> init
  | Some dir ->
    File_tree.Dir.fold dir ~init ~traverse:Sub_dirs.Status.Set.all
      ~f:(fun dir acc ->
        f (Path.append_source prefix_with (File_tree.Dir.path dir)) acc)

let dep expander = function
  | File s ->
    Expander.Or_exn.expand_path expander s
    |> Result.map ~f:(fun path ->
           let+ () = Action_builder.path path in
           [ path ])
  | Alias s ->
    make_alias expander s
    |> Result.map ~f:(fun a ->
           let+ () = Action_builder.alias a in
           [])
  | Alias_rec s ->
    make_alias expander s
    |> Result.map ~f:(fun a ->
           let+ () =
             Build_system.Alias.dep_rec ~loc:(String_with_vars.loc s) a
           in
           [])
  | Glob_files { glob = s; recursive } ->
    let loc = String_with_vars.loc s in
    let path = Expander.Or_exn.expand_path expander s in
    Result.map path ~f:(fun path ->
        let pred =
          Glob.of_string_exn loc (Path.basename path) |> Glob.to_pred
        in
        let dir = Path.parent_exn path in
        let add_dir dir acc =
          let+ paths =
            Action_builder.paths_matching ~loc (File_selector.create ~dir pred)
          and+ acc = acc in
          Path.Set.fold paths ~init:acc ~f:(fun p acc -> p :: acc)
        in
        let+ files =
          let init = Action_builder.return [] in
          if recursive then
            fold_source_dirs dir ~init ~f:add_dir
          else
            add_dir dir init
        in
        List.rev files)
  | Source_tree s ->
    let path = Expander.Or_exn.expand_path expander s in
    Result.map path ~f:(fun path ->
        Action_builder.map ~f:Path.Set.to_list
          (Action_builder.source_tree ~dir:path))
  | Package p ->
    Expander.Or_exn.expand_str expander p
    |> Result.map ~f:(fun pkg ->
           let+ () =
             let pkg = Package.Name.of_string pkg in
             let context = Expander.context expander in
             match Expander.find_package expander pkg with
             | Some (Local pkg) ->
               Action_builder.alias
                 (Build_system.Alias.package_install
                    ~context:(Context.build_context context)
                    ~pkg)
             | Some (Installed pkg) ->
               let version =
                 Dune_project.dune_version @@ Scope.project
                 @@ Expander.scope expander
               in
               if version < (2, 9) then
                 Action_builder.fail
                   { fail =
                       (fun () ->
                         let loc = String_with_vars.loc p in
                         User_error.raise ~loc
                           [ Pp.textf
                               "Dependency on an installed package requires at \
                                least (lang dune 2.9)"
                           ])
                   }
               else
                 let files =
                   List.concat_map
                     ~f:(fun (s, l) ->
                       let dir = Section.Map.find_exn pkg.sections s in
                       List.map l ~f:(fun d ->
                           Path.relative dir (Install.Dst.to_string d)))
                     pkg.files
                 in
                 Action_builder.paths files
             | None ->
               Action_builder.fail
                 { fail =
                     (fun () ->
                       let loc = String_with_vars.loc p in
                       User_error.raise ~loc
                         [ Pp.textf "Package %s does not exist"
                             (Package.Name.to_string pkg)
                         ])
                 }
           in
           [])
  | Universe ->
    Ok
      (let+ () = Action_builder.dep Dep.universe in
       [])
  | Env_var var_sw ->
    Expander.Or_exn.expand_str expander var_sw
    |> Result.map ~f:(fun var ->
           let+ () = Action_builder.env_var var in
           [])
  | Sandbox_config sandbox_config ->
    Ok
      (let+ () = Action_builder.dep (Dep.sandbox_config sandbox_config) in
       [])

let make_interpreter ~f ~expander l =
  Expander.expand_deps_like_field expander ~dep_kind:Optional
    ~f:(fun expander ->
      match Result.List.map l ~f:(f expander) with
      | Ok deps ->
        let+ l = Action_builder.all deps in
        List.concat l
      | Error exn -> Action_builder.fail { fail = (fun () -> reraise exn) })

let unnamed ~expander l =
  let+ _paths = make_interpreter ~f:dep ~expander l in
  ()

let named =
  make_interpreter ~f:(fun expander -> function
    | Bindings.Unnamed p ->
      dep expander p
      |> Result.map ~f:(fun l ->
             let+ l = l in
             List.map l ~f:(fun x -> Bindings.Unnamed x))
    | Named (s, ps) ->
      Result.List.map ps ~f:(dep expander)
      |> Result.map ~f:(fun xs ->
             let+ l = Action_builder.all xs in
             [ Bindings.Named (s, List.concat l) ]))
