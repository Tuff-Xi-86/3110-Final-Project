(* each module we make will be an instance of IntegerMatrix signature from
   matrices.ml *)
module type MatrixOperations = sig
  type t

  val add : t array array -> t array array -> t array array
  val subtract : t array array -> t array array -> t array array
  val multiply : t array array -> t array array -> t array array
  val scale : t -> t array array -> t array array
end

module IntegerMatrixOperations : MatrixOperations with type t = int = struct
  type t = int

  let add mat1 mat2 = mat1
  let subtract mat1 mat2 = mat1
  let multiply mat1 mat2 = mat1
  let scale k mat1 = mat1
end
