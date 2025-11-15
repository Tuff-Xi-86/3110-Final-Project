let users = Hashtbl.create 10

(** [sock_addr_to_string addr] converts a Unix socket address into a
    human-readable "IP:port" string.

    - For [ADDR_INET (ip, port)], it returns e.g. ["127.0.0.1:8080"].
    - Any other address family is rejected.

    @param add The socket address for the client or server.
    @return A canonical "IP:port" string suitable for logging and as a user key.
    @raise Failure if [add] is not [ADDR_INET]. *)
let sock_addr_to_string (add : Unix.sockaddr) =
  match add with
  | ADDR_INET (a, port) -> Unix.string_of_inet_addr a ^ ":" ^ string_of_int port
  | _ -> failwith "unsupported"

(** [broadcast_message key username message] sends [message] to all connected
    clients except the sender identified by [key].

    Each recipient receives a single line in the format:
    ["[<username>]: <message>"] followed by a flush.

    @param key      The sender's connection key (from {!sock_addr_to_string});
                    this client is excluded from broadcast.
    @param username The display name of the sender, used in the formatted line.
    @param message  The already-parsed message line to relay.
    @return An Lwt promise that resolves when all writes and flushes complete.
    @side_effect Writes to every recipient's [Lwt_io.output_channel].
    @threading Runs writes concurrently via [Lwt_list.iter_p].
*)
let broadcast_message key username message =
  Lwt_list.iter_p
    (fun (other_key, (other_username, other_in, other_out)) ->
      if other_key <> key then
        let%lwt () = Lwt_io.fprintlf other_out "[%S]: %s" username message in
        Lwt_io.flush other_out
      else Lwt.return_unit)
    (Hashtbl.fold (fun k v acc -> (k, v) :: acc) users [])

(** [client_handler client_socket_address (client_in, client_out)] manages the
    lifetime of a single client connection on the server.

    Protocol:
    - The client must send its [username] as the very first line.
    - On successful login, the client is registered in {!users} and the server
      broadcasts "<username> has entered the chat." to others.
    - The handler then loops, relaying each subsequent line to all other clients.
    - When EOF is received or an exception bubbles as [None] from [read_line_opt],
      the client is removed from {!users} and a "has left the chat." notice is
      broadcast.

    Logging:
    - Connections, messages, and disconnects are logged to stdout/stderr.

    @param client_socket_address Remote peer address (used to derive the [key]).
    @param client_in  Input channel from the client socket.
    @param client_out Output channel to the client socket.
    @return A promise that resolves when the client disconnects and cleanup is done.
    @side_effect Mutates {!users}; writes to other clients via {!broadcast_message}.
*)
let client_handler client_socket_address (client_in, client_out) =
  let key = sock_addr_to_string client_socket_address in

  (*client should automatically send their username as the first msg*)
  let%lwt username_opt = Lwt_io.read_line_opt client_in in
  match username_opt with
  | None ->
      let%lwt () =
        Lwt_io.printlf "Client %s disconnected before sending username." key
      in
      Lwt.return_unit
  | Some username ->
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
            let%lwt () = Lwt_io.printlf "%s (%s) disconnected." key username in
            let%lwt () = broadcast_message key username "has left the chat." in
            Hashtbl.remove users key;
            Lwt.return_unit
        | Some msg ->
            let%lwt () = Lwt_io.printlf "%s (%s): %S" key username msg in
            let%lwt () = broadcast_message key username msg in
            handle_messages ()
      in
      handle_messages ()

(** [run_server ipaddr port] starts a line-based chat server and blocks the
    current process while serving clients.

    - Binds to [(ipaddr, port)] using
      [Lwt_io.establish_server_with_client_address].
    - For every new connection, spawns {!client_handler}.
    - Never returns (keeps a never-fulfilled promise) unless the process is
      killed.

    @param ipaddr IPv4 address string, e.g. ["0.0.0.0"] or ["127.0.0.1"].
    @param port TCP port to listen on.
    @return This function calls [Lwt_main.run] and does not normally return.
    @raise Unix_error
      if binding fails (e.g., address in use or insufficient perms). *)
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

(** [run_client ipaddr port username] connects to a running chat server and
    enters an interactive session.

    Behavior:
    - Prints a local welcome line.
    - Connects to the server at [(ipaddr, port)] and immediately sends
      [username] as the first line per the server protocol.
    - Concurrency pattern: uses [Lwt.choose] to race two loops:
    - [read_server ()] continuously reads lines from the server and prints them.
    - [send_messages ()] reads user input from stdin and forwards it to server.
    - On server EOF, prints a message and closes the connection gracefully.

    @param ipaddr Server IPv4 address string.
    @param port Server TCP port.
    @param username Display name to register with the server.
    @return
      This function calls [Lwt_main.run] and does not return until the session
      ends (EOF on stdin or server disconnect).
    @raise Unix_error if the TCP connection cannot be established. *)
let run_client ipaddr port username =
  let client () =
    let%lwt () = Lwt_io.printlf "You have joined the chat as %s" username in
    let%lwt server_in, server_out =
      Lwt_io.open_connection (ADDR_INET (Unix.inet_addr_of_string ipaddr, port))
    in
    let%lwt () = Lwt_io.fprintlf server_out "%s" username in
    let%lwt () = Lwt_io.flush server_out in

    let rec read_server () =
      match%lwt Lwt_io.read_line_opt server_in with
      | Some line ->
          let%lwt () = Lwt_io.printl line in
          read_server ()
      | None ->
          let%lwt () = Lwt_io.printl "Server disconnected. Closing client." in
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
    | "client" ->
        if Array.length Sys.argv < 5 then print_usage ()
        else
          let username = Sys.argv.(4) in
          print_endline ("Using username: " ^ username);
          run_client ipaddr port username
    | _ -> print_usage ()
