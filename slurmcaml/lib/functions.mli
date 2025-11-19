module IntegerMatrixOperations : sig
  type t = int

  val add : t array array -> t array array -> t array array
  val subtract : t array array -> t array array -> t array array
  val multiply : t array array -> t array array -> t array array
  val scale : t -> t array array -> t array array
  val transpose : t array array -> t array array
  val map : (t -> 'a) -> t array array -> 'a array array
end

module FloatMatrixOperations : sig
  type t = float

  val add : t array array -> t array array -> t array array
  val subtract : t array array -> t array array -> t array array
  val multiply : t array array -> t array array -> t array array
  val scale : t -> t array array -> t array array
  val transpose : t array array -> t array array
  val map : (t -> 'a) -> t array array -> 'a array array
end
