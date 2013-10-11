open Printf
open Helpers
open HistoryZipper
open QmlContext


let () = Printexc.record_backtrace true

class virtual abstractListModel cppobj = object(self)
  inherit AbstractModel.base_AbstractModel cppobj as super
  method parent _ = QModelIndex.empty
  method index row column parent =
    if (row>=0 && row<self#rowCount parent) then QModelIndex.make ~row ~column:0
    else QModelIndex.empty
  method columnCount _ = 1
  method hasChildren _ = self#rowCount QModelIndex.empty > 0
  val mutable curIndex = -1
  method getHardcodedIndex () = curIndex
  method setHardCodedIndex v =
    if v <> curIndex then (curIndex <- v;
                           self#emit_hardcodedIndexChanged v)
end

class type virtual controller_t = object
  inherit Controller.base_Controller
  method updateDescription: string -> unit
  method emit_fullPath: unit -> unit
end

type options = {
  mutable path: string list;
  mutable zipper: HistoryZipper.zipper;
  mutable root: Types.signature_item Tree.tree;
  mutable cpp_data: (abstractListModel * DataItem.base_DataItem list) list;
  mutable controller: controller_t;
  (* indexes for selected menu*)
  mutable selected: int list;
}

let options =
  { path = [Config.standard_library]
  (* ["/home/kakadu/.opam/4.00.1/lib/ocaml"; "/home/kakadu/.opam/4.00.1/lib/core"] *)
  ; zipper = Obj.magic 1
  ; root = Obj.magic 1
  ; cpp_data = []
  ; controller = Obj.magic 1
  ; selected = [-1]
  }

let () =
  let usage_msg = "This is OCamlBrowser clone written in QtQuick 2.0." in
  Arg.parse
    [ ("-I", Arg.String (fun s -> options.path <- s :: options.path), "Where to look for cmi files")
    ] (fun s -> printf "Unknown parameter %s\n" s; exit 0)
    usage_msg;
  if List.length options.path = 0
  then print_endline "Include paths are empty. Please specufy some via -I <path> option"

let update_paths xs =
  options.path <- xs; (* TODO: remove duplicates *)
  S.(read_modules options.path |> build_tree |> sort_tree)

(* Generated C++ data models for current listviews state *)
let cpp_data_helper (ys: Types.signature_item Tree.tree list list) =
  let f xs =
    let data = List.map xs ~f:(fun {Tree.name;Tree.internal;_} ->
      let cppObj = DataItem.create_DataItem () in
      object(self)
        inherit DataItem.base_DataItem cppObj as super
        method name () = name
        method sort () = internal |> S.sort_of_sig_item
      end) in
    (* creating miniModel for this list *)
    let cppobj = AbstractModel.create_AbstractModel () in
    let innerModelMyRole = 556 in
    AbstractModel.add_role cppobj innerModelMyRole "qwe";

    let o =
      object(self)
        inherit abstractListModel cppobj as super
        method rowCount _ = List.length data

        method data index role =
          let n = QModelIndex.row index in
          if (n<0 || n>= List.length data) then QVariant.empty
          else begin
            if (role=0 || role=innerModelMyRole) (* DisplayRole *)
            then QVariant.of_object (List.nth data ~n)#handler
            else QVariant.empty
          end
      end
    in
    (o,data)
  in
  List.map ys ~f

let initial_cpp_data () : (abstractListModel * DataItem.base_DataItem list) list =
  try
    let xs = Tree.proj options.root [] in
    assert (List.length xs = 1);
    cpp_data_helper xs
  with exc ->
    Printexc.to_string exc |> print_endline;
    printf "Backtrace:\n%s\n%!" (Printexc.get_backtrace ());
    raise exc

let make_full_path selected =
  let indexes = if List.last selected = -1 then List.(selected |> rev |> tl |> rev) else selected in
  assert (List.for_all (fun  x -> x>=0 ) indexes);
  let proj = Tree.proj options.root indexes |> List.take ~n:(List.length indexes) in
  assert (List.length proj = List.length indexes);
  List.map2 proj indexes ~f:(fun xs n -> let x = List.nth xs ~n in x.Tree.name) |> String.concat "."

let describe () =
  let xs = Tree.proj options.root options.selected  in
  assert (options.selected = snd options.zipper.cur);
  let cur_item = List.last xs |> List.nth ~n:(List.last (snd options.zipper.cur)) in
  let b = Buffer.create 500 in
  let fmt = Format.(formatter_of_buffer b) in
  Printtyp.signature fmt [cur_item.Tree.internal];
  Format.pp_print_flush fmt ();
  let desc = Buffer.contents b |> Richify.make in
  options.controller#updateDescription desc

let item_selected mainModel x y : unit =
  let last_row = List.length options.cpp_data - 1 in
  let (new_selected,redraw_from) = Tree.change_state options.selected (x,y) options.root in
  let leaf_selected =
    assert (redraw_from <= List.length options.cpp_data);
    (redraw_from=List.length new_selected)
  in
  options.selected <- new_selected;
  options.controller#emit_fullPath ();
  let cpp_data_head = List.take options.cpp_data ~n:redraw_from in
  if redraw_from <= last_row then begin
    mainModel#beginRemoveRows QModelIndex.empty redraw_from (List.length options.cpp_data-1);
    options.cpp_data <- cpp_data_head;
    mainModel#endRemoveRows ();
  end else begin
    options.cpp_data <- cpp_data_head;
  end;

  let xs = Tree.proj options.root new_selected in
  assert (List.length xs = List.length new_selected);
  if leaf_selected then begin
    HistoryZipper.set_current (make_full_path new_selected, new_selected) options.zipper;
    options.selected <- new_selected;
    describe ()
  end else begin
    let xs = List.drop xs ~n:(List.length cpp_data_head) in
    let zs = cpp_data_helper xs in
    if List.length zs <> 0 then begin
      let from = List.length options.cpp_data in
      let last = from + List.length zs-1 in
      mainModel#beginInsertRows QModelIndex.empty from last;
      options.cpp_data <- options.cpp_data @ zs;
      mainModel#endInsertRows ();
    end;
  end;
  assert (List.length options.cpp_data = List.length new_selected)

(* xs -- new selected indecies *)
let update_view_lists mainModel xs =
  let models = Tree.proj options.root xs in
  (* *)
  mainModel#beginRemoveRows QModelIndex.empty 0 (List.length options.cpp_data - 1);
  options.cpp_data <- [];
  mainModel#endRemoveRows ();
  (* TODO: rewrite generating of functions for listmodel with labels *)
  mainModel#beginInsertRows QModelIndex.empty 0 (List.length xs - 1);
  options.selected <- xs;
  options.cpp_data <- cpp_data_helper models;
  mainModel#endInsertRows ();
  List.iter2 options.cpp_data options.selected ~f:(fun (m,_) v -> m#setHardCodedIndex v)

exception LinkFound of int list
let onLinkActivated controller mainModel s =
  let path = Str.(split (regexp "\\.") s) in
  (* We should know base module of current item *)
  let cur_root_module = List.nth ~n:(List.hd options.selected) options.root.Tree.sons in
  let look_toplevel () =
    try
      (* Looking for link in most top-level entries *)
      let ans = List.fold_left path ~init:(options.root,[]) ~f:(fun (sign,ans) x ->
       match List.findn ~f:(fun item -> Tree.name_of_item item.Tree.internal = x) sign.Tree.sons with
       | Some (item,n) -> (item, n::ans)
       | None -> raise Not_found
      ) in
      Some ans
    with Not_found -> None
  in
  let look_curmodule () =
    try
    (* Looking for link in module which starts current path *)
      Some (List.fold_left path ~init:(cur_root_module,[List.hd options.selected]) ~f:(fun (sign,ans) x ->
       match List.findn ~f:(fun item -> Tree.name_of_item item.Tree.internal = x) sign.Tree.sons with
       | Some (item,n) -> (item, n::ans)
       | None -> raise Not_found
     ))
    with Not_found -> None
  in
  let look_depthvalue () =
    assert (not (HistoryZipper.is_empty options.zipper));
    let last = snd options.zipper.cur in
    assert (List.length last > 1);
    let last = List.take ~n:(List.length last - 1) last in
    let last_module = List.fold_left last ~init: options.root ~f:(fun acc n -> List.nth ~n acc.Tree.sons) in
    assert (Tree.is_module last_module.Tree.internal);
    try
      (* Looking for link in side currently selected module *)
      Some (List.fold_left path ~init:(last_module, List.rev last) ~f:(fun (sign,ans) x ->
       match List.findn ~f:(fun item -> Tree.name_of_item item.Tree.internal = x) sign.Tree.sons with
       | Some (item,n) -> (item, n::ans)
       | None -> raise Not_found
     ))
    with Not_found -> None
  in
  try
    let ans = [look_toplevel (); look_curmodule (); look_depthvalue ()] in
    match List.catMaybes ans with
    | []  -> raise Not_found
    | [r] -> raise (LinkFound (List.rev (snd r)))
    | _ -> assert false
  with
  | LinkFound xs ->
    update_view_lists mainModel xs;

    options.selected <- xs;
    controller#emit_fullPath ();
    (* When we go on link we add last item to backHistory and clear forward history *)
    assert (not (HistoryZipper.is_empty options.zipper));
    HistoryZipper.set_current ~zipper:options.zipper (make_full_path xs, xs);
    describe ()
  | Not_found -> () (* printf "No link found!\n%!" *)


let do_update_paths model xs =
  if options.path <> xs then begin
    (* there we need to clear model ... *)
    model#beginRemoveRows QModelIndex.empty 0 (List.length options.cpp_data-1);
    options.cpp_data <- [];
    model#endRemoveRows ();
    options.root <- update_paths xs;
    (* ... and repopuly it *)
    if options.root.Tree.sons <> [] then begin
      model#beginInsertRows QModelIndex.empty 0 0;
      options.cpp_data <- initial_cpp_data ();
      options.selected <- [-1];
      model#endInsertRows ()
    end else
      options.selected <- [];
  end

let main () =
  let cpp_model = AbstractModel.create_AbstractModel () in
  let myDefaultRoleMainModel = 555 in
  AbstractModel.add_role cpp_model myDefaultRoleMainModel "homm";

  let model = object(self)
    inherit abstractListModel cpp_model as super
    method rowCount _ = List.length options.cpp_data
    method data index role =
      let n = QModelIndex.row index in
      if (n<0 || n>= List.length options.cpp_data) then QVariant.empty
      else begin
        if (role=0 || role=myDefaultRoleMainModel) (* DisplayRole *)
        then QVariant.of_object (List.nth options.cpp_data ~n |> fst)#handler
        else QVariant.empty
      end
  end in

  let controller_cppobj = Controller.create_Controller () in
  let controller = object(self)
    inherit Controller.base_Controller controller_cppobj as super
    method forwardTo s i =
      printf "OCaml: forward to '%s', %d\n%!" s i;
      HistoryZipper.find_forward ~zipper:options.zipper s;
      options.selected <- options.zipper.cur |> snd;
      update_view_lists model options.selected;
      self#emit_fullPath ();
      describe ()

    method backTo s i =
      printf "OCaml: back to '%s', %d\n%!" s i;
      HistoryZipper.find_back ~zipper:options.zipper s;
      options.selected <- options.zipper.cur |> snd;
      update_view_lists model options.selected;
      self#emit_fullPath ();
      describe ()

    method linkActivated = onLinkActivated self model
    method onItemSelected x y =
      try
        item_selected model x y
      with exc ->
        Printexc.to_string exc |> print_endline;
        printf "Backtrace:\n%s\n%!" (Printexc.get_backtrace ());
        exit 0
    method paths () = options.path
    method setPaths xs = do_update_paths model xs
    val mutable desc = None
    method isHasData () = match desc with Some _ -> true | _ -> false
    method getDescr () =
      match desc with
        | Some x -> x
        | None   ->
            eprintf "App have tried to access description which should not exist now";
            "<no description. Bug!>"
    method emit_fullPath () =
      self#emit_fullPathChanged (self#fullPath ())
    method fullPath () = make_full_path options.selected
    method updateDescription info =
      if self#isHasData () then begin
        desc <- Some info;
      end else begin
        desc <- Some info;
        self#emit_hasDataChanged true;
      end;
      self#emit_descChanged info
  end in

  options.root <- update_paths options.path;
  options.controller <- controller;
  options.zipper <- HistoryZipper.create ();
  options.cpp_data <- initial_cpp_data ();
  set_context_property ~ctx:(get_view_exn ~name:"rootContext") ~name:"myModel" model#handler;
  set_context_property ~ctx:(get_view_exn ~name:"rootContext") ~name:"controller" controller#handler

let () = Callback.register "doCaml" main
