open Slurmcaml.Functions
open Slurmcaml.Matrixutils

(* TODO stuff: evaluate functions and implement map, do error checking on
   matrices, fix usage stuff at bottom*)

(* unix util funcs *)
let sock_addr_to_string (add : Unix.sockaddr) =
  match add with
  | ADDR_INET (a, port) -> Unix.string_of_inet_addr a ^ ":" ^ string_of_int port
  | _ -> failwith "unsupported"

let format_status_string status job output =
  Printf.sprintf "%s|%s|%s" status job output

(*Map util functions [SHOULD GO IN A LIB ML FILE]*)
type expr =
  | Const of float
  | Var of string
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Div of expr * expr
  | Pow of expr * expr
  | Neg of expr
  | Func of string * expr

(*TODO: evaluate functions & implement MAP*)

(* reads a matrix from input channel and *)
let return_matrix valuetype job channel =
  let server_in = channel in
  match valuetype with
  | "int" -> (
      match job with
      | "add" ->
          let%lwt mat1 = read_int_matrix_input server_in in
          let%lwt mat2 = read_int_matrix_input server_in in
          Lwt.return (IntMatrix (IntegerMatrixOperations.add mat1 mat2))
      | "subtract" ->
          let%lwt mat1 = read_int_matrix_input server_in in
          let%lwt mat2 = read_int_matrix_input server_in in
          Lwt.return (IntMatrix (IntegerMatrixOperations.subtract mat1 mat2))
      | "multiply" ->
          let%lwt mat1 = read_int_matrix_input server_in in
          let%lwt mat2 = read_int_matrix_input server_in in
          Lwt.return (IntMatrix (IntegerMatrixOperations.multiply mat1 mat2))
      | "scale" ->
          let%lwt k = Lwt_io.read_line server_in in
          let%lwt mat = read_int_matrix_input server_in in
          Lwt.return
            (IntMatrix (IntegerMatrixOperations.scale (int_of_string k) mat))
      | "transpose" ->
          let%lwt mat = read_int_matrix_input server_in in
          Lwt.return (IntMatrix (IntegerMatrixOperations.transpose mat))
      | _ -> failwith "not an implemented function")
  | "float" -> (
      match job with
      | "add" ->
          let%lwt mat1 = read_float_matrix_input server_in in
          let%lwt mat2 = read_float_matrix_input server_in in
          Lwt.return (FloatMatrix (FloatMatrixOperations.add mat1 mat2))
      | "subtract" ->
          let%lwt mat1 = read_float_matrix_input server_in in
          let%lwt mat2 = read_float_matrix_input server_in in
          Lwt.return (FloatMatrix (FloatMatrixOperations.subtract mat1 mat2))
      | "multiply" ->
          let%lwt mat1 = read_float_matrix_input server_in in
          let%lwt mat2 = read_float_matrix_input server_in in
          Lwt.return (FloatMatrix (FloatMatrixOperations.multiply mat1 mat2))
      | "scale" ->
          let%lwt k = Lwt_io.read_line server_in in
          let%lwt mat = read_float_matrix_input server_in in
          Lwt.return
            (FloatMatrix (FloatMatrixOperations.scale (float_of_string k) mat))
      | "transpose" ->
          let%lwt mat = read_float_matrix_input server_in in
          Lwt.return (FloatMatrix (FloatMatrixOperations.transpose mat))
      | _ -> failwith "not an implemented function")
  | _ -> failwith "not an implemented type"

(* this currently reads a matrix (sent in the form of a csv) from what the
   server has written to the user, along with the value type of the matrix and
   the operation to perform, computes the operation, and writes the result to
   the server's out, followed by done head node will need to send only the work
   that this node should do, along with the parameters above*)
let run_client ipaddr port instanceName =
  let client () =
    let%lwt () =
      Lwt_io.printlf "worker has joined the fleet as %s" instanceName
    in
    let%lwt server_in, server_out =
      Lwt_io.open_connection (ADDR_INET (Unix.inet_addr_of_string ipaddr, port))
    in
    let%lwt () = Lwt_io.fprintlf server_out "%s" instanceName in
    let%lwt () = Lwt_io.flush server_out in

    let rec handle_job () =
      let%lwt job_opt = Lwt_io.read_line_opt server_in in
      match job_opt with
      | None ->
          let%lwt () = Lwt_io.printlf "Disconnected from server." in
          Lwt.return_unit
      | Some job ->
          let%lwt () = Lwt_io.printlf "Received job: %s" job in
          let%lwt valuetype = Lwt_io.read_line server_in in
          let%lwt res = return_matrix valuetype job server_in in
          let%lwt () = print_matrix res server_out in
          let%lwt () = Lwt_io.fprintl server_out "done" in
          let%lwt () =
            Lwt_io.printlf "Executed command with exit code: [TODO]"
          in
          let%lwt () = Lwt_io.printlf "Completed job: %s" job in
          let%lwt () =
            Lwt_io.write_line server_out
              (format_status_string "AVAILABLE" job "TODO EXIT CODE")
          in
          let%lwt () = Lwt_io.flush server_out in
          handle_job ()
    in
    handle_job ()
  in
  Lwt_main.run (client ())

let _ =
  let print_usage () =
    Printf.printf "Usage: %s <server | client>\n" Sys.argv.(0)
  in
  if Array.length Sys.argv < 4 then print_usage ()
  else
    let ipaddr = Sys.argv.(2) in
    let port =
      match int_of_string_opt Sys.argv.(3) with
      | Some p -> p
      | None ->
          Printf.printf "Invalid port number: %s\n" Sys.argv.(3);
          exit 1
    in

    print_endline ("Using IP: " ^ ipaddr ^ " Port: " ^ string_of_int port);
    match Sys.argv.(1) with
    | "worker" ->
        if Array.length Sys.argv < 5 then print_usage ()
        else
          let instanceName = Sys.argv.(4) in
          print_endline ("Worker Name: " ^ instanceName);
          run_client ipaddr port instanceName
    | _ -> failwith "wrong usage"
