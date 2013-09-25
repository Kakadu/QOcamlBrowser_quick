open Printf
open Helpers

let () = Printexc.record_backtrace true

type options =
    { mutable path: string list
    ; mutable with_color: bool
    }

let options =
  { path = [] (* ["/home/kakadu/.opam/4.00.1/lib/ocaml"; "/home/kakadu/.opam/4.00.1/lib/core"] *)
  ; with_color = true
  }


let () =
  let usage_msg =
    [ "This is OCamlBrowser clone written in QtQuick 2.0."
    ] |> String.concat "\n"
  in
  Arg.parse
    [ ("-I", Arg.String (fun s -> options.path <- s :: options.path), "Where to look for cmi files")
    ] (fun s -> printf "Unknown parameter %s\n" s; exit 0)
    usage_msg;
  if List.length options.path = 0
  then print_endline "Include paths are empty. Please specufy some via -I <path> option"

open QmlContext

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

let update_paths xs =
  options.path <- xs;
  S.(read_modules options.path |> build_tree |> sort_tree)

let root : Types.signature_item Tree.tree ref = ref (update_paths options.path)
let selected: int list ref = ref [-1]
let cpp_data: (abstractListModel * DataItem.base_DataItem list) list ref  = ref []
let last_described = ref []

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
    AbstractModel.add_role cppobj 555 "qwe";

    let o =
      object(self)
        inherit abstractListModel cppobj as super
        method rowCount _ = List.length data

        method data index role =
          let r = QModelIndex.row index in
          if (r<0 || r>= List.length data) then QVariant.empty
          else begin
            if (role=0 || role=555) (* DisplayRole *)
            then QVariant.of_object (List.nth data ~n:r)#handler
            else QVariant.empty
          end
      end
    in
    (o,data)
  in
  List.map ys ~f

let initial_cpp_data () : (abstractListModel * DataItem.base_DataItem list) list =
  let xs = Tree.proj !root [-1] in
  assert (List.length xs = 1);
  cpp_data_helper xs

let describe controller new_selected =
  last_described := new_selected;
  let xs = Tree.proj !root new_selected in
  let cur_item = List.last xs |> List.nth ~n:(List.last new_selected) in
  let b = Buffer.create 500 in
  let fmt = Format.(formatter_of_buffer b) in
  Printtyp.signature fmt [cur_item.Tree.internal];
  Format.pp_print_flush fmt ();
  let desc = Buffer.contents b |> Richify.make in
  controller#updateDescription desc

let item_selected controller mainModel x y : unit =
  let last_row = List.length !cpp_data - 1 in
  let (new_selected,redraw_from) = Tree.change_state !selected (x,y) !root in
  let leaf_selected =
    assert (redraw_from <= List.length !cpp_data);
    (redraw_from=List.length new_selected)
  in
  selected := new_selected;
  controller#emit_fullPath ();
  let cpp_data_head = List.take !cpp_data ~n:redraw_from in
  if redraw_from <= last_row then begin
    mainModel#beginRemoveRows QModelIndex.empty redraw_from (List.length !cpp_data-1);
    cpp_data := cpp_data_head;
    mainModel#endRemoveRows ();
  end else begin
    cpp_data := cpp_data_head;
  end;

  let xs = Tree.proj !root new_selected in
  assert (List.length xs = List.length new_selected);
  if leaf_selected then
    describe controller new_selected
  else begin
    let xs = List.drop xs ~n:(List.length cpp_data_head) in
    let zs = cpp_data_helper xs in
    if List.length zs <> 0 then begin
      let from = List.length !cpp_data in
      let last = from + List.length zs-1 in
      mainModel#beginInsertRows QModelIndex.empty from last;
      cpp_data := !cpp_data @ zs;
      mainModel#endInsertRows ();
    end;
  end;
  assert (List.length !cpp_data = List.length new_selected)

exception LinkFound of int list
let onLinkActivated controller mainModel s =
  let path = Str.(split (regexp "\\.") s) in
  (* We should know base module of current item *)
  let cur_root_module = List.nth ~n:(List.hd !selected) !root.Tree.sons in
  let look_toplevel () =
    try
      (* Looking for link in most top-level entries *)
      let ans = List.fold_left path ~init:(!root,[]) ~f:(fun (sign,ans) x ->
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
      Some (List.fold_left path ~init:(cur_root_module,[List.hd !selected]) ~f:(fun (sign,ans) x ->
       match List.findn ~f:(fun item -> Tree.name_of_item item.Tree.internal = x) sign.Tree.sons with
       | Some (item,n) -> (item, n::ans)
       | None -> raise Not_found
     ))
    with Not_found -> None
  in
  let look_depthvalue () =
    let last = !last_described in
    assert (List.length last > 1);
    let last = List.take ~n:(List.length last - 1) last in
    let last_module = List.fold_left last ~init: !root ~f:(fun acc n -> List.nth ~n acc.Tree.sons) in
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
    if ans = [None;None;None] then raise Not_found;
    let r = match ans with
      | (Some x)::_ -> x
      | _::(Some x)::_ -> x
      | _::_::(Some x)::_ -> x
      | _____ -> assert false
    in
    raise (LinkFound (List.rev (snd r)))
  with
  | LinkFound xs ->
    let models = Tree.proj !root xs in
    mainModel#beginRemoveRows QModelIndex.empty 0 (List.length !selected - 1);
    cpp_data := [];
    mainModel#endRemoveRows ();
    (* TODO: rewrite generating of functions for listmodel with labels *)
    mainModel#beginInsertRows QModelIndex.empty 0 (List.length xs - 1);
    selected := xs;
    cpp_data := cpp_data_helper models;

    mainModel#endInsertRows ();
    List.iter2 !cpp_data !selected ~f:(fun (m,_) v -> m#setHardCodedIndex v);
    selected := xs;
    controller#emit_fullPath ();
    last_described := xs;
    describe controller xs
  | Not_found -> () (* printf "No link found!\n%!" *)


let do_update_paths model xs =
  if options.path <> xs then begin
    (* there we need to clear model ... *)
    model#beginRemoveRows QModelIndex.empty 0 (List.length !cpp_data-1);
    cpp_data := [];
    model#endRemoveRows ();
    root := update_paths xs;
    (* ... and repopuly it *)
    if !root.Tree.sons <> [] then begin
      model#beginInsertRows QModelIndex.empty 0 0;
      cpp_data := initial_cpp_data ();
      selected := [-1];
      model#endInsertRows ()
    end else
      selected := [];
  end

let main () =
  cpp_data := initial_cpp_data ();

  let cpp_model = AbstractModel.create_AbstractModel () in
  AbstractModel.add_role cpp_model 555 "homm";

  let model = object(self)
    inherit abstractListModel cpp_model as super
    method rowCount _ = List.length !cpp_data
    method data index role =
      let r = QModelIndex.row index in
      if (r<0 || r>= List.length !cpp_data) then QVariant.empty
      else begin
        if (role=0 || role=555) (* DisplayRole *)
        then QVariant.of_object (List.nth !cpp_data ~n:r |> fst)#handler
        else QVariant.empty
      end
  end in

  let controller_cppobj = Controller.create_Controller () in
  let controller = object(self)
    inherit Controller.base_Controller controller_cppobj as super
    method linkActivated = onLinkActivated self model
    method onItemSelected x y =
      try
        item_selected self model x y
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
    method fullPath () =
      let indexes = if List.last !selected = -1 then List.(!selected |> rev |> tl |> rev) else !selected in
      (*printf "List.length indexes = %d\n" (List.length indexes);*)
      assert (List.for_all (fun  x -> x>=0 ) indexes);
      let proj = Tree.proj !root indexes |> List.take ~n:(List.length indexes) in
      (*printf "List.length proj = %d\n%!" (List.length proj);*)
      assert (List.length proj = List.length indexes);
      List.map2 proj indexes ~f:(fun xs n -> let x = List.nth xs ~n in x.Tree.name) |> String.concat "."

    method updateDescription info =
      if self#isHasData () then begin
        desc <- Some info;
      end else begin
        desc <- Some info;
        self#emit_hasDataChanged true;
      end;
      self#emit_descChanged info
  end in

  set_context_property ~ctx:(get_view_exn ~name:"rootContext") ~name:"myModel" model#handler;
  set_context_property ~ctx:(get_view_exn ~name:"rootContext") ~name:"controller" controller#handler

let () = Callback.register "doCaml" main
