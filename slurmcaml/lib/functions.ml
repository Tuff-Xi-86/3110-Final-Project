(* each module we make will be an instance of IntegerMatrix signature from
   matrices.ml *)
module type MatrixOperations = sig
  type t

  val add : t array array -> t array array -> t array array
  val subtract : t array array -> t array array -> t array array
  val multiply : t array array -> t array array -> t array array
  val scale : t -> t array array -> t array array
  val transpose : t array array -> t array array
  val map : (t -> 'a) -> t array array -> 'a array array
end

module IntegerMatrixOperations : MatrixOperations with type t = int = struct
  type t = int

  (* HN can't send the whole matrix, has to only send the specific rows to
     operate on*)
  let add_rows row1 row2 =
    let length = Array.length row1 in
    let elt i = row1.(i) + row2.(i) in
    Array.init length elt

  let subtract_rows row1 row2 =
    let length = Array.length row1 in
    let elt i = row1.(i) - row2.(i) in
    Array.init length elt

  let add mat1 mat2 =
    let length = Array.length mat1 in
    let calc i = add_rows mat1.(i) mat2.(i) in
    Array.init length calc

  let subtract mat1 mat2 =
    let length = Array.length mat1 in
    let calc i = subtract_rows mat1.(i) mat2.(i) in
    Array.init length calc

  let extract_column j mat =
    let length = Array.length mat in
    let elt i = mat.(i).(j) in
    Array.init length elt

  let dot_product row1 row2 =
    let sum = ref 0 in
    for i = 0 to Array.length row1 - 1 do
      sum := !sum + (row1.(i) * row2.(i))
    done;
    !sum

  let calc_row i mat1 mat2 =
    let elt j = dot_product mat1.(i) (extract_column j mat2) in
    Array.init (Array.length mat2.(0)) elt

  let multiply mat1 mat2 =
    Array.init (Array.length mat1) (fun i -> calc_row i mat1 mat2)

  let scale_row k row = Array.init (Array.length row) (fun i -> k * row.(i))

  let scale k mat1 =
    Array.init (Array.length mat1) (fun i -> scale_row k mat1.(i))

  let transpose mat1 =
    Array.init (Array.length mat1.(0)) (fun i -> extract_column i mat1)

  let map f mat1 = Array.map (fun x -> Array.map f x) mat1
end

module FloatMatrixOperations : MatrixOperations with type t = float = struct
  type t = float

  (* HN can't send the whole matrix, has to only send the specific rows to
     operate on*)
  let add_rows row1 row2 =
    let length = Array.length row1 in
    let elt i = row1.(i) +. row2.(i) in
    Array.init length elt

  let subtract_rows row1 row2 =
    let length = Array.length row1 in
    let elt i = row1.(i) -. row2.(i) in
    Array.init length elt

  let add mat1 mat2 =
    let length = Array.length mat1 in
    let calc i = add_rows mat1.(i) mat2.(i) in
    Array.init length calc

  let subtract mat1 mat2 =
    let length = Array.length mat1 in
    let calc i = subtract_rows mat1.(i) mat2.(i) in
    Array.init length calc

  let extract_column j mat =
    let length = Array.length mat in
    let elt i = mat.(i).(j) in
    Array.init length elt

  let dot_product row1 row2 =
    let sum = ref 0.0 in
    for i = 0 to Array.length row1 - 1 do
      sum := !sum +. (row1.(i) *. row2.(i))
    done;
    !sum

  let calc_row i mat1 mat2 =
    let elt j = dot_product mat1.(i) (extract_column j mat2) in
    Array.init (Array.length mat2.(0)) elt

  let multiply mat1 mat2 =
    Array.init (Array.length mat1) (fun i -> calc_row i mat1 mat2)

  let scale_row k row = Array.init (Array.length row) (fun i -> k *. row.(i))

  let scale k mat1 =
    Array.init (Array.length mat1) (fun i -> scale_row k mat1.(i))

  let transpose mat1 =
    Array.init (Array.length mat1.(0)) (fun i -> extract_column i mat1)

  let map f mat1 = Array.map (fun x -> Array.map f x) mat1
end
