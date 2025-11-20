open Functions

type result =
  | IntMatrix of int array array
  | FloatMatrix of float array array

(*prints a matrix, type checking against IntMatrix and FloatMatrix*)
let print_matrix res channel =
  match res with
  | IntMatrix mat ->
      let%lwt () = Lwt_io.fprintl channel (string_of_int (Array.length mat)) in
      let%lwt () =
        Lwt_io.fprintl channel (string_of_int (Array.length mat.(0)))
      in
      let%lwt () =
        Lwt_list.iter_s
          (fun x ->
            Lwt_io.fprintl channel
              (String.concat "," (List.map string_of_int (Array.to_list x))))
          (Array.to_list mat)
      in
      Lwt_io.fprintl channel "end"
  | FloatMatrix mat ->
      let%lwt () = Lwt_io.fprintl channel (string_of_int (Array.length mat)) in
      let%lwt () =
        Lwt_io.fprintl channel (string_of_int (Array.length mat.(0)))
      in
      let%lwt () =
        Lwt_list.iter_s
          (fun x ->
            Lwt_io.fprintl channel
              (String.concat "," (List.map string_of_float (Array.to_list x))))
          (Array.to_list mat)
      in
      Lwt_io.fprintl channel "end"

let set_row_int i mat row =
  let row =
    Array.of_list (List.map int_of_string (String.split_on_char ',' row))
  in
  mat.(i) <- row

let set_row_float i mat row =
  let row =
    Array.of_list (List.map float_of_string (String.split_on_char ',' row))
  in
  mat.(i) <- row

(* first has to send value type (int, float, etc.), then # of rows, then # of columns*)
(* TODO: implement error checking for matrix size*)
let read_int_matrix_input channel =
  let%lwt row = Lwt_io.read_line channel in
  let%lwt columns = Lwt_io.read_line channel in
  let mat =
    Array.init (int_of_string row) (fun _ ->
        Array.make (int_of_string columns) 0)
  in
  let rec set_row i =
    let%lwt line = Lwt_io.read_line channel in
    match line with
    | "end" -> Lwt.return ()
    | s ->
        set_row_int i mat s;
        set_row (i + 1)
  in
  let%lwt () = set_row 0 in
  Lwt.return mat

let read_float_matrix_input channel =
  let%lwt row = Lwt_io.read_line channel in
  let%lwt columns = Lwt_io.read_line channel in
  let mat =
    Array.init (int_of_string row) (fun _ ->
        Array.make (int_of_string columns) 0.0)
  in
  let rec set_row i =
    let%lwt line = Lwt_io.read_line channel in
    match line with
    | "end" -> Lwt.return ()
    | s ->
        set_row_float i mat s;
        set_row (i + 1)
  in
  let%lwt () = set_row 0 in
  Lwt.return mat
