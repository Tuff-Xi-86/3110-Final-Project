let users = Hashtbl.create 10
let head_props = ref None
let jobs = Queue.create ()
let job_table = Hashtbl.create 10

let sock_addr_to_string (add : Unix.sockaddr) =
  match add with
  | ADDR_INET (a, port) -> Unix.string_of_inet_addr a ^ ":" ^ string_of_int port
  | _ -> failwith "unsupported"

let find_available_worker () =
  Hashtbl.fold
    (fun key (username, in_, out_, available) acc ->
      if available then Some (key, username, in_, out_) else acc)
    users None

let format_status_string status job output =
  Printf.sprintf "%s|%s|%s" status job output

let parse_status_string status_string =
  match String.split_on_char '|' status_string with
  | status :: job :: output_parts ->
      let output = String.concat "|" output_parts in
      Some (status, job, output)
  | _ -> None

let client_handler client_socket_address (client_in, client_out) =
  let key = sock_addr_to_string client_socket_address in

  (*client should automatically send their node type as the first msg*)
  let%lwt node_type_opt = Lwt_io.read_line_opt client_in in
  match node_type_opt with
  | None ->
      let%lwt () =
        Lwt_io.printlf "Client %s disconnected before sending node type." key
      in
      Lwt.return_unit
  | Some node_type -> (
      match node_type with
      | "HEAD" ->
          let%lwt () = Lwt_io.printlf "HEAD node connected: %s" key in
          let%lwt () =
            head_props := Some (key, client_in, client_out);
            Lwt.return_unit
          in
          let rec handle_jobs () =
            let%lwt job_opt = Lwt_io.read_line_opt client_in in
            match job_opt with
            | None ->
                let%lwt () = Lwt_io.printlf "HEAD node %s disconnected." key in
                Lwt.return_unit
            | Some "view_jobs" ->
                let%lwt () = Lwt_io.fprintlf client_out "Current Job Table" in
                let entries =
                  Hashtbl.fold
                    (fun job (completed, worker, output) acc ->
                      let status_str =
                        if completed then "COMPLETED" else "PENDING"
                      in
                      let worker_str =
                        match worker with
                        | Some w -> w
                        | None -> "N/A"
                      in
                      let output_str =
                        match output with
                        | Some o -> o
                        | None -> "N/A"
                      in
                      Printf.sprintf
                        "Job: %s | Status: %s | Worker: %s | Output: %s" job
                        status_str worker_str output_str
                      :: acc)
                    job_table []
                in
                let%lwt () =
                  Lwt_list.iter_s
                    (fun line -> Lwt_io.fprintlf client_out "%s" line)
                    (List.rev entries)
                in
                let%lwt () = Lwt_io.fprintlf client_out "END_OF_JOBS" in
                handle_jobs ()
            | Some job ->
                let%lwt () = Lwt_io.printlf "Received job from HEAD: %s" job in
                let%lwt () = Lwt.return (Queue.add job jobs) in
                let%lwt () =
                  Lwt.return (Hashtbl.add job_table job (false, None, None))
                in
                handle_jobs ()
          in
          handle_jobs ()
      | instanceName ->
          let username = instanceName in
          let%lwt () =
            Hashtbl.replace users key (username, client_in, client_out, true);
            Lwt.return_unit
          in
          let%lwt () = Lwt_io.printlf "%s (%S) connected." key username in

          let rec handle_status () =
            let%lwt status = Lwt_io.read_line_opt client_in in
            match status with
            | None ->
                let%lwt () =
                  Lwt_io.printlf "%s (%s) disconnected." key username
                in
                Hashtbl.remove users key;
                Lwt.return_unit
            | Some status -> (
                let%lwt () =
                  Lwt_io.printlf "%s (%s): Status Update: %S" key username
                    status
                in

                (*statuses are formatted as follows: <AVAILABLE> <JOB>
                  <OUTPUT>*)
                match parse_status_string status with
                | None ->
                    let%lwt () =
                      Lwt_io.printlf "%s (%s): Malformed status string: %s" key
                        username status
                    in
                    handle_status ()
                | Some ("AVAILABLE", job, output) ->
                    Hashtbl.replace users key
                      (username, client_in, client_out, true);
                    Hashtbl.replace job_table job
                      (true, Some username, Some output);
                    handle_status ()
                | _ -> handle_status ())
          in

          let rec send_jobs () =
            match Queue.is_empty jobs with
            | true ->
                let%lwt () = Lwt_unix.sleep 1.0 in
                send_jobs ()
            | false -> (
                match find_available_worker () with
                | None ->
                    let%lwt () = Lwt_unix.sleep 1.0 in
                    send_jobs ()
                | Some (worker_key, worker_name, worker_in, worker_out) ->
                    let job = Queue.pop jobs in
                    let%lwt () =
                      Lwt_io.printlf "Assigning job %s to worker %s (%s)" job
                        worker_name worker_key
                    in
                    let%lwt () =
                      Lwt.return
                        (Hashtbl.replace job_table job
                           (false, Some worker_name, None))
                    in
                    let%lwt () = Lwt_io.write_line worker_out job in
                    let%lwt () = Lwt_io.flush worker_out in
                    Hashtbl.replace users worker_key
                      (worker_name, worker_in, worker_out, false);
                    send_jobs ())
          in
          Lwt.choose [ handle_status (); send_jobs () ])

let run_server ipaddr port =
  let server () =
    let%lwt () = Lwt_io.printlf "I am the server." in
    let%lwt running_server =
      Lwt_io.establish_server_with_client_address
        (ADDR_INET (Unix.inet_addr_of_string ipaddr, port))
        client_handler
    in
    let never_resolved, _ = Lwt.wait () in
    never_resolved
  in
  Lwt_main.run (server ())

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
    | "server" -> run_server ipaddr port
    | "head" ->
        if Array.length Sys.argv < 4 then print_usage ()
        else run_head ipaddr port
    | "worker" ->
        if Array.length Sys.argv < 5 then print_usage ()
        else
          let instanceName = Sys.argv.(4) in
          print_endline ("Worker Name: " ^ instanceName);
          run_client ipaddr port instanceName
    | _ -> print_usage ()
