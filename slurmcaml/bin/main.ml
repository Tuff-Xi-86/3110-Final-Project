let users = Hashtbl.create 10

let sock_addr_to_string (add : Unix.sockaddr) =
  match add with
  | ADDR_INET (a, port) -> Unix.string_of_inet_addr a ^ ":" ^ string_of_int port
  | _ -> failwith "unsupported"

let broadcast_message key username message =
  Lwt_list.iter_p
    (fun (other_key, (other_username, other_in, other_out)) ->
      if other_key <> key then
        let%lwt () = Lwt_io.fprintlf other_out "[%S]: %s" username message in
        Lwt_io.flush other_out
      else Lwt.return_unit)
    (Hashtbl.fold (fun k v acc -> (k, v) :: acc) users [])

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
          Lwt.return_unit
      | instanceName ->
          let username = instanceName in
          let%lwt () =
            Hashtbl.replace users key (username, client_in, client_out);
            Lwt.return_unit
          in
          let%lwt () = Lwt_io.printlf "%s (%S) connected." key username in

          let%lwt () = broadcast_message key username "has entered the chat." in

          (*da first message*)
          let rec handle_messages () =
            let%lwt message = Lwt_io.read_line_opt client_in in
            match message with
            | None ->
                let%lwt () =
                  Lwt_io.printlf "%s (%s) disconnected." key username
                in
                let%lwt () =
                  broadcast_message key username "has left the chat."
                in
                Hashtbl.remove users key;
                Lwt.return_unit
            | Some msg ->
                let%lwt () = Lwt_io.printlf "%s (%s): %S" key username msg in
                let%lwt () = broadcast_message key username msg in
                handle_messages ()
          in
          handle_messages ())

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

    let rec read_server () =
      match%lwt Lwt_io.read_line_opt server_in with
      | Some line ->
          let%lwt () = Lwt_io.printl line in
          read_server ()
      | None ->
          let%lwt () = Lwt_io.printl "Server disconnected. Closing instance." in
          let%lwt () = Lwt_io.close server_out in
          let%lwt () = Lwt_io.close server_in in
          Lwt.return_unit
    in
    let rec send_messages () =
      match%lwt Lwt_io.read_line_opt Lwt_io.stdin with
      | Some msg ->
          let%lwt () = Lwt_io.write_line server_out msg in
          let%lwt () = Lwt_io.flush server_out in
          send_messages ()
      | None -> Lwt.return_unit
    in
    Lwt.choose [ read_server (); send_messages () ]
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
          let%lwt () = Lwt_io.write_line server_out job in
          let%lwt () = Lwt_io.flush server_out in
          send_job ()
      | None -> Lwt.return_unit
    in
    send_job ()
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
        else run_client ipaddr port "HEAD"
    | "worker" ->
        if Array.length Sys.argv < 5 then print_usage ()
        else
          let instanceName = Sys.argv.(4) in
          print_endline ("Worker Name: " ^ instanceName);
          run_client ipaddr port instanceName
    | _ -> print_usage ()
