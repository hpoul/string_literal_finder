## 2.0.0

- **Breaking**: `nonNls<T>` is now `nonNls<T extends Object>`. Without the
  bound `T` was inferred from the surrounding context, so `x ?? nonNls('')`
  made the whole expression nullable and broke compilation elsewhere. Only
  `nonNls(<something nullable>)` stops compiling, which suppressed nothing
  anyway.

## 1.0.0

- preparing null safety

## 0.1.1+1

- improve documentation.

## 0.1.0

- Initial version, created by Stagehand
