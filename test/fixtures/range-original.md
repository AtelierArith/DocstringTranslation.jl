```julia
(:)(start, [step], stop)
```

Range operator. `a:b` constructs a range from `a` to `b` with a step size equal to +1, which produces:

  * a [`UnitRange`](@ref) when `a` and `b` are integers, or
  * a [`StepRange`](@ref) when `a` and `b` are characters, or
  * a [`StepRangeLen`](@ref) when `a` and/or `b` are floating-point.

`a:s:b` is similar but uses a step size of `s` (a [`StepRange`](@ref) or [`StepRangeLen`](@ref)). See also [`range`](@ref) for more control.

To create a descending range, use `reverse(a:b)` or a negative step size, e.g. `b:-1:a`. Otherwise, when `b < a`, an empty range will be constructed and normalized to `a:a-1`.

The operator `:` is also used in indexing to select whole dimensions, e.g. in `A[:, 1]`.

`:` is also used to [`quote`](@ref) code, e.g. `:(x + y) isa Expr` and `:x isa Symbol`. Since `:2 isa Int`, it does *not* create a range in indexing: `v[:2] == v[2] != v[begin:2]`.
