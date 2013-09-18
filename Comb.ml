open Parser
open Printf
external (|>): 'a -> ('a -> 'b) -> 'b  = "%revapply"

let html_escape: string -> string = fun s ->
  s
  |> Str.global_replace (Str.regexp "<") "&lt;"
  |> Str.global_replace (Str.regexp ">") "&gt;"
  |> Str.global_replace (Str.regexp " ") "&nbsp;"
  |> Str.global_replace (Str.regexp "\n") "<br/>"

type tag = Control | Define | Structure | Char | Infix | Label | UIndent
let string_of_tag = function
  | Control -> "Control"
  | _ -> "___"

(* Next colors are from labltk. Some of them can be invalid. TODO: check this *)
let color_of_tag = function
  | Control -> "blue"
  | Define  -> "forestgreen"
  | Structure -> "purple"
  | Char   -> "gray"
  | Infix  -> "#8b3a3a" (* "indianred4" *)
  | Label  -> "brown"
  | UIndent -> "midnightblue"

type lexeme = int*int*string*Parser.token*(tag option)
let string_of_lexeme (s,e,str,_,tag) =
  sprintf "(%d,%d,'%s',_,%s)" s e str (match tag with Some x -> string_of_tag x | None -> "None")

let print_lexemes arr =
  print_endline "Lexemes start:";
  Array.iter (fun l -> print_endline (string_of_lexeme l)) arr;
  print_endline "End of lexemes"

type lastpos = int
(* stream is where last token ended, cur number of lexeme, array of lexemes *)
type stream = {lp: lastpos; n: int; arr: lexeme array}
type 'a result =
  | Parsed of 'a*stream
  | Failed
type 'a parse = stream -> 'a result

let rec many p s =
  match p s with
  | Failed -> Parsed ([],s)
  | Parsed (r,s2) -> begin
      match many p s2 with
      | Parsed ([],_)  -> Parsed([r], s2)
      | Parsed (r2,s3) -> Parsed(r::r2, s3)
      | Failed  -> assert false
  end

(* + in BNF *)
let many1 p s =
  match p s with
  | Failed -> Failed
  | Parsed (r,s2) -> begin
      match many p s2 with
      | Parsed ([],_)  -> Parsed([r], s2)
      | Parsed (r2,s3) -> Parsed(r::r2, s3)
      | Failed  -> assert false
  end

let (-->) p1 f s =
  match p1 s with
  | Failed -> Failed
  | Parsed (r,stream) -> Parsed(f r stream.lp, stream)

let seq p1 p2 s =
  match p1 s with
  | Failed -> Failed
  | Parsed (r,s) -> p2 r s.lp s

let (|>) = seq

let (<|>) p1 p2 s =
  match p1 s with
  | Parsed (r,z) -> Parsed (r,z)
  | Failed -> p2 s

let lident ({ n; arr; lp }) =
  if n >= Array.length arr then Failed else
  match arr.(n) with
  | (_,lp,_,LIDENT s,_) -> Parsed(s, { lp; n=n+1; arr })
  | _ -> Failed

let uident ({ n; arr; lp } as s) =
  if s.n >= Array.length s.arr then Failed else
  match s.arr.(s.n) with
  | (_,lp,_,UIDENT s,_) -> Parsed(s, { lp; n=n+1; arr })
  | _ -> Failed

let ident = lident <|> uident

let dot ({ n; arr; lp } as s) =
  if s.n >= Array.length s.arr then Failed else
  match s.arr.(s.n) with
  | (_,lp,_,DOT,_) -> Parsed ((), { lp; n=n+1; arr=s.arr })
  | _ -> Failed

let exc_keyword ({ n; arr;_ } as s) =
  if n >= Array.length arr then Failed else
  match s.arr.(s.n) with
  | (_,lp,_,EXCEPTION,_) -> Parsed ((), { lp; n=n+1; arr=s.arr })
  | _ -> Failed

let val_keyword ({ n; arr;_ } as s) =
  if s.n >= Array.length s.arr then Failed else
  match s.arr.(s.n) with
  | (_,lp,_,VAL,_) -> Parsed ((), { lp; n=n+1; arr=s.arr })
  | _ -> Failed

let token ({ n; arr;_ } ) =
  if n >= Array.length arr then Failed else
  match arr.(n) with
  | (_,lp,s,_,tag)  -> Parsed (s, { lp; n=n+1; arr })

let link s =
  let p1 : string parse = uident |> fun ident _ -> dot --> fun _ pos -> ident in
  match many1 p1 s with
  | Parsed (xs,s1) -> begin
      match lident s1 with
      | Parsed (name,s3) ->
        let ans = if xs = [] then name else String.concat "." xs ^ "." ^ name in
        Parsed (ans,s3)
      | Failed -> Failed
  end
  | Failed -> Failed


let main_parser main_str (token_n,arr) =
  (*print_lexemes arr;*)
  let last_pos = ref 0 in
  let cur_token_n = ref token_n in
  let arr_len = Array.length arr in
  let ans = Buffer.create 100 in
  let put_str s =
    (*printf "Adding string '%s' to buffer\n" s;*)
    Buffer.add_string ans s
  in

  let eat_token ({lp; n; arr} ) =
    assert (n < Array.length arr);
    let (st,en,tok_str,tok,tag) = arr.(n) in
    let () = if lp < st && st <> 0 then (
      let s = StringLabels.sub main_str ~pos:(lp) ~len:(st - lp) in
      put_str (html_escape s)
    ) in
    let s = html_escape tok_str in
    let s = match tag with
      | Some tag -> sprintf "<font color='%s'>%s</font>" (color_of_tag tag) s
      | None -> s
    in
    Parsed (s, {lp=en; n=n+1; arr})
  in
  let with_prefix p s =
    (p --> fun r _ -> begin
      let pos = s.lp in
      let next = match s.arr.(s.n) with (s,_,_,_,_) -> s in
      let len = next - pos in
      let s = StringLabels.sub main_str ~pos ~len in
      (html_escape s ^ r)
    end) s
  in
  let valdef s =
    let p =
      val_keyword |> fun () _ ->
      ident      --> fun ident pos -> sprintf "<font color='green'>val</font>&nbsp;%s" ident
    in
    with_prefix p s
  in
  let excdef =
    with_prefix (
      exc_keyword |> fun () _ ->
        ident    --> fun ident pos -> sprintf "<font color='green'>exception</font>&nbsp;%s" ident
    )
  in
  let link_wrap s =
    (link  --> fun name _ -> begin
      let pos = s.lp in
      let next = match s.arr.(s.n) with (s,_,_,_,_) -> s in
      let len = next - pos in
      let s = StringLabels.sub main_str ~pos ~len in
      (*printf "Link '%s' found. Getting prefix: pos=%d, next=%d, len=%d, substr=%s\n%!" name pos next len s;
      *)
      (sprintf "%s<a href='%s'><font color='blue'>%s</font></a>" s name name)
    end) s
  in
  let pp = excdef <|> valdef <|> link_wrap <|> eat_token in
  while !cur_token_n < arr_len do
    match pp { n= !cur_token_n; lp= !last_pos; arr } with
    | Parsed (r,s) ->
      put_str r;
      cur_token_n := s.n;
      last_pos := s.lp;
    | Failed -> assert false
  done;
  let ans_str = Buffer.contents ans in
  ans_str
