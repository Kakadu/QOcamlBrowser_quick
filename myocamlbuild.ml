open Ocamlbuild_plugin
open Command

(* Generic pkg-config(1) support. *)

let os = Ocamlbuild_pack.My_unix.run_and_read "uname -s"

let pkg_config flags package =
  let cmd tmp =
    Command.execute ~quiet:true &
    Cmd( S [ A "pkg-config"; A ("--" ^ flags); A package; Sh ">"; A tmp]);
    List.map (fun arg -> A arg) (string_list_of_file tmp)
  in
  with_temp_file "pkgconfig" "pkg-config" cmd

let pkg_config_lib ~lib (*~has_lib ~stublib *) =
  let cflags = (*(A has_lib) :: *) pkg_config "cflags" lib in (*
  let stub_l = [A (Printf.sprintf "-l%s" stublib)] in *)
  let libs_l = pkg_config "libs-only-l" lib in
  let libs_L = pkg_config "libs-only-L" lib in
  let linker = match os with
  | "Linux\n" -> [A "-Wl,-no-as-needed"]
  | _ -> []
  in
  let make_opt o arg = S [ A o; arg ] in
  let mklib_flags = (List.map (make_opt "-ldopt") linker) @ libs_l @ libs_L in
  let compile_flags = List.map (make_opt "-ccopt") cflags in
  let lib_flags = List.map (make_opt "-cclib") libs_l in
  let link_flags = List.map (make_opt "-ccopt") (linker @ libs_L) in (*
  let stublib_flags = List.map (make_opt "-dllib") stub_l  in *)
  let tag = Printf.sprintf "use_%s" lib in
  flag ["c"; "ocamlmklib"; tag] (S mklib_flags);
  flag ["c"; "compile"; "mocml_generated"] (S compile_flags);
  flag ["c"; "compile"; "mocml_generated"] (S [A"-cc";A"g++"; A"-ccopt";A"-std=c++0x";A"-ccopt";A"-fPIC"]);
  flag ["c"; "compile"; "mocml_generated"] (S [A"-ccopt";A"-Dprotected=public"]);
  flag ["link"; "ocaml"; tag] (S (link_flags @ lib_flags));
  flag ["link"; "ocaml"; tag] (make_opt "-cclib" (A"-lstdc++"));
  (*
  flag ["link"; "ocaml"; "library"; "byte"; tag] (S stublib_flags) *)
  ()

let () =
  dispatch begin function
  | Before_rules ->
    (*
    rule  "compile C++ files rule"
         ~prod:"%.o"
         ~deps:"src/DataItem_c.o"
         begin fun env build ->
           let a = env _a in
           let tags = tags_of_pathname a++"library"++"object"++"archive" in
           Cmd(S([ A"g++"; A"-o"; A libname ]
                 @ (List.map (fun o -> A o) c_objs) @
                 [  A(l_ zlib_libdir); A zlib_lib; T tags ]
                )
              )
         end; *)
    flag  [ "cpp"; "compile"; ] (S [A"-package";A"lablqml"]);
    ()
  | After_rules ->
    rule "Qt_moc: %.h -> moc_%.c"
      ~prods:["%(path:<**/>)moc_%(modname:<*>).c"]
      ~dep:"%(path)%(modname).h"
      (begin fun env build ->
        tag_file (env "%(path)%(modname).h") ["qtmoc"];
        Cmd (S [A "moc"; P (env "%(path)%(modname).h"); Sh ">"; P (env "%(path)moc_%(modname).c")]);
       end);
    (*
    tag_file "src/DataItem_c.h" ["qtmoc"];
    *)
    pkg_config_lib ~lib:"Qt5Quick";
    pkg_config_lib ~lib:"Qt5Widgets";
    flag ["link"; "ocaml"; "native"; "use_cppstubs" ] (S[A"src/libcppstubs.a"]);
    flag ["compile"; "c"; "mocml_generated"] (S [A"-package";A"lablqml"]);
    dep ["compile"; "c"] [ "src/DataItem_c.h"
                         ; "src/Controller_c.h"
                         ; "src/AbstractModel_c.h"];
    (*
    flag ["link"; "ocaml"; "native"; "use_qt5"]
          (S[A"-cclib"; A"-lQt5Quick"
            ;A"-cclib"; A"-lQt5Gui"
            ;A"-cclib"; A"-lQt5Widgets"
            ;A"-cclib"; A"-lQt5Network"
            ;A"-cclib"; A"-lQt5Core"
            ;A"-cclib"; A"-lQt5Qml"
            ;A"-cclib"; A"-lstdc++"]
                                                                ) *)
    ()
  | _ -> ()
  end
