open Helpers
open HistoryModel
open Printf
open QmlContext

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
    printf "beginRemoveRows(_,%d,%d)\n%!" first last;
    super#beginRemoveRows index first last
end

type item = string*int list
class type model_t = object
  method prepend: item list -> unit
  method clear: unit
  method find: f:(item -> bool) -> (item list * item) option
  method count1 : int
end

exception ItemFound of item list * item
type zipper = {
  mutable cur: item;
  mutable backModel: model_t;
  mutable forwardModel: model_t;
  mutable is_empty: bool;
}

let make_model name =
  let cppobj = HistoryModel.create_HistoryModel () in
  let text_role = 690 in
  HistoryModel.add_role cppobj text_role "text";
  let data : item list ref = ref [] in
  let backModel = object(self)
    inherit listModelHelper cppobj
    method rowCount _ = List.length !data
    method data index role =
      let n = QModelIndex.row index in
      if (n<0 || n>= List.length !data) then QVariant.empty
      else if (role=0 || role=text_role)
      then (
        let ans = (List.nth !data ~n |> fst) in
        printf "data: return %s on index=%d\n%!" ans n;
        QVariant.of_string ans
      )
      else QVariant.empty

    method prepend xs =
      if xs<>[] then begin
        self#beginInsertRows QModelIndex.empty 0 (List.length xs - 1);
        data := xs @ !data;
        self#endInsertRows ()
      end
    method clear =
      if !data <> [] then begin
        self#beginRemoveRows QModelIndex.empty 0 (List.length !data - 1);
        data := [];
        self#endRemoveRows ()
      end

    method dropN n =
      printf "self#dropN %d\n%!" n;
      printf "old data: %s\n%!" (List.to_string ~f:fst !data);
      assert (n>=0);
      if n <> 0 then begin
		(* right piece of code 
        self#beginRemoveRows QModelIndex.empty 0 (n - 1);
		*)
		(* this is buggy one: see https://bugreports.qt-project.org/browse/QTBUG-33847 *)
		self#beginRemoveRows QModelIndex.empty (List.length !data - n) (List.length !data - 1);
        data := List.drop !data ~n;
        self#endRemoveRows ()
      end;
      printf "new data: %s\n%!" (List.to_string ~f:(fst) !data)

    (* should return reversed list *)
    method find ~f =
      printf "zipper#find in %s\n%!" (List.to_string ~f:fst !data);
      try
        let _ = List.fold_left ~init:[] !data ~f:(fun acc x ->
          if f x then raise (ItemFound (acc,x))
          else x::acc
        ) in
        None
      with ItemFound (xs,item) ->
        self#dropN (List.length xs + 1); (* +1 because we remove xs and _found_ element *)
        Some (xs,item)
    method count1 = List.length !data
  end in
  set_context_property ~ctx:(get_view_exn ~name:"rootContext") ~name backModel#handler;
  backModel

let create () =
  let backModel = (make_model "backModel" :> model_t) in
  let forwardModel = (make_model "forwardModel" :> model_t) in
  { cur=Obj.magic 1; backModel; forwardModel; is_empty=true }

let set_current cur ~zipper =
  assert (String.length (fst cur) > 0);
  if zipper.is_empty then begin zipper.cur <- cur; zipper.is_empty <- false end
  else begin
    zipper.backModel#prepend [zipper.cur];
    zipper.forwardModel#clear;
    zipper.cur <- cur
  end

let to_string z =
  sprintf "(%d,%s,%d)" z.backModel#count1 (fst z.cur) z.forwardModel#count1

let find_back name ~zipper =
  printf "Looking for '%s' in back history\n%!" name;
  match zipper.backModel#find ~f:(fun (x,_) -> x=name) with
  | None -> failwith "can't find history item backward"
  | Some (xs,newcur) ->
    zipper.forwardModel#prepend [zipper.cur];
    zipper.forwardModel#prepend xs;
    zipper.cur <- newcur

let find_forward name ~zipper =
  match zipper.forwardModel#find ~f:(fun (x,_) -> x=name) with
  | None -> failwith "can't find history item forward"
  | Some (xs,newcur) ->
    zipper.backModel#prepend [zipper.cur];
    zipper.backModel#prepend xs;
    zipper.cur <- newcur

let is_empty z = z.is_empty
