type result =
  | IntMatrix of int array array
  | FloatMatrix of float array array

val print_matrix : result -> Lwt_io.output_channel -> unit Lwt.t
val read_int_matrix_input : Lwt_io.input_channel -> int array array Lwt.t
val read_float_matrix_input : Lwt_io.input_channel -> float array array Lwt.t
