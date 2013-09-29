open Helpers
open Printf
open QmlContext
open HistoryModel

class virtual listModelHelper cppobj = object(self)
  inherit base_HistoryModel cppobj as super
  method parent _ = QModelIndex.empty
  method index row column parent =
    if (row>=0 && row<self#rowCount parent) then QModelIndex.make ~row ~column:0
    else QModelIndex.empty
  method columnCount _ = 1
  method hasChildren _ = self#rowCount QModelIndex.empty > 0
  method! beginRemoveRows index first last =
    (* TODO: add to generated code asserts about first <= last *)
    (* TODO: add to generated code labeled arguments *)
    assert (last>=first);
    super#beginRemoveRows index first last
end

class type ttt = object
  method take:    count:int -> unit
  method takeAll: unit
  method prepend: string list -> unit
  method count:   int
  method items:   string list
end
type t = { mutable back: ttt; mutable forward: ttt }
let o =  { back = Obj.magic 1
         ; forward = Obj.magic 1
         }

let make_model name =
  let text_role = 690 in
  let cppobj = HistoryModel.create_HistoryModel () in
  HistoryModel.add_role cppobj text_role "text";

  let data : string list ref = ref [] in
  let o = object(self)
    inherit listModelHelper cppobj
    method rowCount _ = List.length !data
    method data index role =
      let n = QModelIndex.row index in
      if (n<0 || n>= List.length !data) then QVariant.empty
      else if (role=0 || role=text_role)
      then QVariant.of_string (List.nth !data ~n)
      else QVariant.empty

    method take ~count:n =
      assert (n <= List.length !data);
      if n>0 then (
        self#beginRemoveRows QModelIndex.empty 0 (n-1);
        Ref.replace data ~f:(List.take ~n);
        self#endRemoveRows ()
      )

    method takeAll =
      if !data <> [] then begin
        self#beginRemoveRows QModelIndex.empty 0 (List.length !data - 1);
        data := [];
        self#endRemoveRows ()
      end

    method prepend xs =
      let l = List.length xs in
      assert (l > 0);
      (*printf "prepending: %s\n%!" (List.to_string ~f:(fun x -> x) xs);*)
      self#beginInsertRows QModelIndex.empty 0 (l-1);
      Ref.replace data ~f:((@)xs);
      self#endInsertRows ()

    method count = List.length !data
    method items = !data
  end in
  set_context_property ~ctx:(get_view_exn ~name:"rootContext") ~name o#handler;
  (o :> ttt)

let init () =
  o.back <- make_model "backModel";
  o.forward <- make_model "forwardModel"
