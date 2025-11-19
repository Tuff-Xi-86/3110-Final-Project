let run_head ipaddr port =
  let head () =
    let%lwt () = Lwt_io.printlf "Connected to Server as HEAD node" in
    let%lwt server_in, server_out =
      Lwt_io.open_connection (ADDR_INET (Unix.inet_addr_of_string ipaddr, port))
    in
    let%lwt () = Lwt_io.fprintlf server_out "HEAD" in
    let%lwt () = Lwt_io.flush server_out in

    let rec send_job () =
      match%lwt Lwt_io.read_line_opt Lwt_io.stdin with
      | Some job ->
          let%lwt () = Lwt_io.printlf "Sending job: %s" job in
          let%lwt () = Lwt_io.write_line server_out job in
          let%lwt () = Lwt_io.flush server_out in
          send_job ()
      | None -> Lwt.return_unit
    in

    let rec receive_responses () =
      let%lwt response_opt = Lwt_io.read_line_opt server_in in
      match response_opt with
      | Some response ->
          if response = "END_OF_JOBS" then
            let%lwt () = Lwt_io.printlf "End of job list." in
            receive_responses ()
          else
            let%lwt () = Lwt_io.printlf "Job Status: \n %s" response in
            receive_responses ()
      | None -> Lwt.return_unit
    in

    Lwt.choose [ send_job (); receive_responses () ]
  in
  Lwt_main.run (head ())

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
    | "head" ->
        if Array.length Sys.argv < 4 then print_usage ()
        else run_head ipaddr port
    | _ -> failwith "wrong usage"
