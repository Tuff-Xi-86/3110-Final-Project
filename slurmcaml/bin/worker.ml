open Slurmcaml.Functions

let sock_addr_to_string (add : Unix.sockaddr) =
  match add with
  | ADDR_INET (a, port) -> Unix.string_of_inet_addr a ^ ":" ^ string_of_int port
  | _ -> failwith "unsupported"

let format_status_string status job output =
  Printf.sprintf "%s|%s|%s" status job output

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
          let%lwt status =
            Lwt_process.exec (Lwt_process.shell (job ^ " && sleep 10"))
          in
          let exit_code =
            match status with
            | Unix.WEXITED n -> n
            | _ -> -1
          in
          let%lwt () =
            Lwt_io.printlf "Executed command with exit code: %d" exit_code
          in
          let%lwt () = Lwt_io.printlf "Completed job: %s" job in
          let%lwt () =
            Lwt_io.write_line server_out
              (format_status_string "AVAILABLE" job (string_of_int exit_code))
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
