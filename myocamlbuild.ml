open Ocamlbuild_plugin
open Command

let () = 
  dispatch begin function
  | After_rules ->
    flag ["link"; "ocaml"; "native"; "use_qt5"]
          (S[A"-cclib"; A"-lQt5Quick"
            ;A"-cclib"; A"-lQt5Gui"
            ;A"-cclib"; A"-lQt5Widgets"
            ;A"-cclib"; A"-lQt5Network"
            ;A"-cclib"; A"-lQt5Core"
            ;A"-cclib"; A"-lQt5Qml"
            ;A"-cclib"; A"-lstdc++"]
          )
  | _ -> ()
  end



