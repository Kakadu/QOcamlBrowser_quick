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
  flag ["c"; "ocamlmklib"; "use_qt5"] (S mklib_flags);

  List.iter (fun tag ->
    flag ["c"; "compile"; tag] (S compile_flags);
    flag ["c"; "compile"; tag] (S [A"-cc";A"g++"; A"-ccopt";A"-std=c++0x";A"-ccopt";A"-fPIC"]);
    flag ["c"; "compile"; tag] (S [A"-ccopt";A"-Dprotected=public"]);
    flag ["c"; "compile"; tag] (S [A"-package";A"lablqml"]);
    flag ["c"; "compile"; tag] (S [A"-ccopt";A"-I."]);
  ) ["mocml_generated"; "qtmoc_generated"; "qt_resource_file"];

  flag ["link"; "ocaml"; "use_qt5"] (S (link_flags @ lib_flags));
  flag ["link"; "ocaml"; "use_qt5"] (make_opt "-cclib" (A"-lstdc++"));
  ()

let () =
  dispatch begin function
  | After_rules ->
    rule "Qt_moc: %.h -> moc_%.c"
      ~prods:["%(path:<**/>)moc_%(modname:<*>).c"]
      ~dep:"%(path)%(modname).h"
      (begin fun env build ->
        tag_file (env "%(path)%(modname).h") ["qtmoc"];
        Cmd (S [A "moc"; P (env "%(path)%(modname).h"); Sh ">"; P (env "%(path)moc_%(modname).c")]);
       end);

    rule "Qt resource: %.qrc -> qrc_%.c"
      ~prods:["%(path:<**/>)qrc_%(modname:<*>).c"]
      ~dep:"%(path)%(modname).qrc"
      (begin fun env build -> (*
        tag_file (env "%(path)%(modname).h") ["qt_resource"]; *)
        Cmd(S[ A"rcc"; A"-name"; A(env "%(modname)"); P (env "%(path)%(modname).qrc")
             ; A "-o"; P (env "%(path)qrc_%(modname).c")])
       end);

    pkg_config_lib ~lib:"Qt5Quick Qt5Widgets"; (*
    pkg_config_lib ~lib:"Qt5Widgets"; *)
    dep ["link"; "ocaml"; "use_qrc_stub"] ["src/qrc_resources.o"];
    flag ["link"; "ocaml"; "native"; "use_cppstubs" ] (S[A"src/libcppstubs.a"]);
    dep ["compile"; "c"] [ "src/DataItem_c.h"
                         ; "src/Controller_c.h"
                         ; "src/HistoryModel_c.h"
                         ; "src/AbstractModel_c.h"];
    ()
  | _ -> ()
  end
