sealed class Failure {}

class AuthFailure extends Failure {}
class NetworkFailure extends Failure {}
class StorageFailure extends Failure {}
class CryptoFailure extends Failure {}

sealed class Result<S, F extends Failure> {}

class Success<S, F extends Failure> extends Result<S, F> {
  final S value;
  Success(this.value);
}

class ErrorResult<S, F extends Failure> extends Result<S, F> {
  final F failure;
  ErrorResult(this.failure);
}
