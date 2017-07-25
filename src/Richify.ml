open StdLabels
open Parser
open Printf
open Comb

let string_of_tag = function
  | DO  -> "do"
  | DOT -> "."
  | UIDENT s -> "UIDENT " ^ s
  | LIDENT s -> "LIDENT " ^ s
  | _ -> "_"

let make s =
  let buffer = Lexing.from_string s in
  Location.init buffer "";
  Location.input_name := "";

  let rich_info = ref [] in
  let add_info x = rich_info := x :: !rich_info in
  let () = try
    let last = ref (EOF, 0, 0) in
    while true do
      let token = Lexer.token buffer
      and start = Lexing.lexeme_start buffer
      and stop = Lexing.lexeme_end buffer in
      let tag = match token with
        | AMPERAMPER | AMPERSAND | BARBAR | DO | DONE | DOWNTO | ELSE  | FOR
        | IF       | LAZY        | MATCH  | OR | THEN | TO     | TRY   | WHEN
        | WHILE    | WITH          -> Some Control
        | AND      | AS       | BAR      | CLASS    | CONSTRAINT | EXCEPTION    | EXTERNAL
        | FUN      | FUNCTION | FUNCTOR  | IN       | INHERIT    | INITIALIZER  | LET
        | METHOD   | MODULE   | MUTABLE  | NEW      | OF         | PRIVATE      | REC
        | TYPE     | VAL      | VIRTUAL  -> Some Define
        | BEGIN    | END      | INCLUDE      | OBJECT      | OPEN      | SIG
        | STRUCT     -> Some Structure
        | CHAR _   | STRING _ -> Some Char
        | INFIXOP1 _        | INFIXOP2 _        | INFIXOP3 _        | INFIXOP4 _        | PREFIXOP _
        | BACKQUOTE | HASH          ->  Some Infix
        | LABEL _        | OPTLABEL _        | QUESTION        | TILDE          ->  Some Label
        | UIDENT _ -> Some UIndent
        | LIDENT _ ->
            begin match !last with
              | (QUESTION | TILDE), _, _ ->  Some Label
              | _ -> None
            end
        | COLON -> begin
            match !last with
              | (LIDENT x, lstart, lstop) ->
                  if lstop = start then add_info (lstart,lstop,x, token,Some Label);
                  None
              | _ -> None
          end
        | EOF -> raise End_of_file
        | _ -> None
      in
      add_info (start,stop,StringLabels.sub ~pos:start ~len:(stop-start) s,token,tag);
    done
  with
    | End_of_file -> ()
    | Lexer.Error (err, loc) -> ()
  in
  Comb.main_parser s (0, Array.of_list (List.rev !rich_info))
