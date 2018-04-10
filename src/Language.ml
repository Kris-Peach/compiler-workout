(* Opening a library for generic programming (https://github.com/dboulytchev/GT).
   The library provides "@type ..." syntax extension and plugins like show, etc.
*)
open GT

(* Opening a library for combinator-based syntax analysis *)
open Ostap
open Combinators
                         
(* States *)
module State =
  struct
                                                                
    (* State: global state, local state, scope variables *)
    type t = {g : string -> int; l : string -> int; scope : string list}

    (* Empty state *)
    let empty = failwith "Not implemented"

    (* Update: non-destructively "modifies" the state s by binding the variable x 
       to value v and returns the new state w.r.t. a scope
    *)
    let update x v s = failwith "Not implemented"
                                
    (* Evals a variable in a state w.r.t. a scope *)
    let eval s x = failwith "Not implemented" 

    (* Creates a new scope, based on a given state *)
    let enter st xs = failwith "Not implemented"

    (* Drops a scope *)
    let leave st st' = failwith "Not implemented"

  end
    
(* Simple expressions: syntax and semantics *)
module Expr =
  struct
    
    (* The type for expressions. Note, in regular OCaml there is no "@type..." 
       notation, it came from GT. 
    *)
    @type t =
    (* integer constant *) | Const of int
    (* variable         *) | Var   of string
    (* binary operator  *) | Binop of string * t * t with show

    (* Available binary operators:
        !!                   --- disjunction
        &&                   --- conjunction
        ==, !=, <=, <, >=, > --- comparisons
        +, -                 --- addition, subtraction
        *, /, %              --- multiplication, division, reminder
    *)
      
    (* Expression evaluator

          val eval : state -> t -> int
 
       Takes a state and an expression, and returns the value of the expression in 
       the given state.
    *)                                                       
    let int2bool x = x !=0
    let bool2int x = if x then 1 else 0

    let binop operation left_op right_op =
	match operation with
        | "+" -> left_op + right_op
        | "-" -> left_op - right_op
        | "*" -> left_op * right_op
        | "/" -> left_op / right_op
        | "%" -> left_op mod right_op
        | "<" -> bool2int (left_op < right_op)
        | ">" -> bool2int (left_op > right_op)
        | "<=" -> bool2int (left_op <= right_op)
        | ">=" -> bool2int (left_op >= right_op)
        | "==" -> bool2int (left_op == right_op)
        | "!=" -> bool2int (left_op != right_op)
        | "&&" -> bool2int (int2bool left_op && int2bool right_op)
        | "!!" -> bool2int (int2bool left_op || int2bool right_op)
        | _ -> failwith "Not implemented yet"
  

    let rec eval state expr = 
        match expr with
        | Const c -> c
        | Var v -> state v
        | Binop (operation, left_expr, right_expr) ->
        let left_op = eval state left_expr in
        let right_op = eval state right_expr in
        binop operation left_op right_op

    let binop_transforming binoplist = List.map (fun op -> ostap($(op)), (fun left_op right_op -> Binop (op, left_op, right_op))) binoplist    
(* Expression parser. You can use the following terminals:

         IDENT   --- a non-empty identifier a-zA-Z[a-zA-Z0-9_]* as a string
         DECIMAL --- a decimal constant [0-9]+ as a string
                                                                                                                  
    *)
    ostap (                                      
      parse:
	  !(Ostap.Util.expr
          (fun x -> x)
          [|
            `Lefta, binop_transforming ["!!"];
            `Lefta, binop_transforming ["&&"];
            `Nona,  binop_transforming [">="; ">"; "<="; "<"; "=="; "!="];
            `Lefta, binop_transforming ["+"; "-"];
            `Lefta, binop_transforming ["*"; "/"; "%"]
          |]
	
	primary
	);
        primary: x:IDENT {Var x} | c:DECIMAL {Const c} | -"(" parse -")" 
    )
    
  end
                    
(* Simple statements: syntax and sematics *)
module Stmt =
  struct

    (* The type for statements *)
    @type t =
    (* read into the variable           *) | Read   of string
    (* write the value of an expression *) | Write  of Expr.t
    (* assignment                       *) | Assign of string * Expr.t
    (* composition                      *) | Seq    of t * t 
    (* empty statement                  *) | Skip
    (* conditional                      *) | If     of Expr.t * t * t
    (* loop with a pre-condition        *) | While  of Expr.t * t
    (* loop with a post-condition       *) | Repeat of t * Expr.t
    (* call a procedure                 *) | Call   of string * Expr.t list with show
                                                                    
    (* The type of configuration: a state, an input stream, an output stream *)
    type config = Expr.state * int list * int list 

    (* Statement evaluator

         val eval : config -> t -> config

       Takes a configuration and a statement, and returns another configuration
    *)
    let rec eval (state, input, output) stmt = 
        match stmt with
        | Assign (x, expr) -> (Expr.update x (Expr.eval state expr) state, input, output)
        | Read (x) -> 
                (match input with
                | z::tail -> (Expr.update x z state, tail, output)
                | [] -> failwith "Empty input stream")
        | Write (expr) -> (state, input, output @ [(Expr.eval state expr)])
        | Seq (frts_stmt, scnd_stmt) -> (eval (eval (state, input, output) frts_stmt ) scnd_stmt)
        | Skip -> (state, input, output)
        | If (expr, frts_stmt, scnd_stmt) -> if Expr.eval state expr !=0 then eval (state, input, output) frts_stmt else eval (state, input, output) scnd_stmt
        | While (expr, st) -> if Expr.eval state expr !=0 then eval (eval (state, input, output) st) stmt else (state, input, output)
        | Repeat (expr, st) ->
          let (state', input', output') = eval (state, input, output) st in
          if Expr.eval state' expr == 0 then eval (state', input', output') stmt else (state', input', output')
                               
    (* Statement parser *)
    ostap (
      parse: seq | stmt;
      stmt: assign | read | write | if_ | while_ | for_ | repeat_ | skip;
      assign: x:IDENT -":=" expr:!(Expr.parse) {Assign (x, expr)};
      read: -"read" -"(" x:IDENT -")" {Read x};
      write: -"write" -"("expr:!(Expr.parse) -")" {Write expr};
      if_: "if" expr:!(Expr.parse) "then" st:parse "fi" {If (expr, st, Skip)} 
         | "if" expr:!(Expr.parse) "then" frts_stmt:parse else_elif:else_or_elif "fi" {If (expr, frts_stmt, else_elif)}; else_or_elif: else_ | elif_;
      else_: "else" st:parse {st};
      elif_: "elif" expr:!(Expr.parse) "then" frts_stmt:parse scnd_stmt:else_or_elif {If (expr, frts_stmt, scnd_stmt)};
      while_: "while" expr:!(Expr.parse) "do" st:parse "od" {While (expr, st)};
      for_: "for" init:parse "," expr:!(Expr.parse) "," frts_stmt:parse "do" scnd_stmt:parse "od" {Seq (init, While (expr, Seq(scnd_stmt, frts_stmt)))};
      repeat_: "loop" st:parse "until" expr:!(Expr.parse) {Repeat (expr, st)};
      skip: "skip" {Skip};
      seq: frts_stmt:stmt -";" scnd_stmt:parse {Seq (frts_stmt, scnd_stmt)}
    )
      
  end

(* Function and procedure definitions *)
module Definition =
  struct

    (* The type for a definition: name, argument list, local variables, body *)
    type t = string * (string list * string list * Stmt.t)

    ostap (
      parse: empty {failwith "Not implemented"}
    )

  end
    
(* The top-level definitions *)

(* The top-level syntax category is a pair of definition list and statement (program body) *)
type t = Definition.t list * Stmt.t    

(* Top-level evaluator

     eval : t -> int list -> int list

   Takes a program and its input stream, and returns the output stream
*)
let eval (defs, body) i = failwith "Not implemented"
                                   
(* Top-level parser *)
let parse = failwith "Not implemented"
