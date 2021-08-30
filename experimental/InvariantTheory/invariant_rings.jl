export invariant_ring, primary_invariants, secondary_invariants

###############################################

mutable struct InvRing{FldT, GrpT, PolyElemT, PolyRingT, ActionT, SingularActionT}
  field::FldT
  poly_ring::PolyRingT

  group::GrpT
  action::Vector{ActionT}
  action_singular::Vector{SingularActionT}

  modular::Bool

  primary::Vector{PolyElemT}
  secondary::Vector{PolyElemT}
  irreducible_secondary::Vector{PolyElemT}
  fundamental::Vector{PolyElemT}

  # Cache some stuff on the Singular side
  # (possibly removed at some point)
  reynolds_singular::Singular.smatrix
  molien_singular::Singular.smatrix
  primary_singular # the type is different depending on the characteristic...

  function InvRing(K::FldT, G::GrpT, action::Vector{ActionT}) where {FldT <: Field, GrpT <: AbstractAlgebra.Group, ActionT}
    n = degree(G)
    R, = PolynomialRing(K, "x" => 1:n, cached = false)
    R_sing = singular_ring(R)
    action_singular = identity.([change_base_ring(R_sing, g) for g in action])
    PolyRingT = typeof(R)
    PolyElemT = elem_type(R)
    SingularActionT = eltype(action_singular)
    z = new{FldT, GrpT, PolyElemT, PolyRingT, ActionT, SingularActionT}()
    z.field = K
    z.poly_ring = R
    z.group = G
    z.action = action
    z.action_singular = action_singular
    z.modular = true
    if iszero(characteristic(K))
      z.modular = false
    else
      if !iszero(mod(order(G), characteristic(K)))
        z.modular = false
      end
    end
    return z
  end
end

################################################################################
#
#  Field access
#
################################################################################

coefficient_ring(I::InvRing) = I.field

polynomial_ring(I::InvRing) = I.poly_ring

action(I::InvRing) = I.action

_action_singular(I::InvRing) = I.action_singular

group(I::InvRing) = I.group

ismodular(I::InvRing) = I.modular

function invariant_ring(M::Vector{<: MatrixElem})
  return invariant_ring(base_ring(M[1]), M)
end

invariant_ring(matrices::MatrixElem{T}...) where {T} = invariant_ring(collect(matrices))

function invariant_ring(K::Field, M::Vector{<: MatrixElem})
  return invariant_ring(matrix_group([change_base_ring(K, g) for g in M]))
end

#######################################################

@doc Markdown.doc"""
    invariant_ring(G::MatrixGroup)

Return the invariant ring of the finite matrix group `G`.
    
CAVEAT: The creation of invariant rings is lazy in the sense that no explicit computations are done until specifically invoked (for example by the `primary_invariants` function).

# Examples
```jldoctest
julia> K, a = CyclotomicField(3, "a")
(Cyclotomic field of order 3, a)

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0])
[0   0   1]
[1   0   0]
[0   1   0]

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1])
[1   0        0]
[0   a        0]
[0   0   -a - 1]

julia> G = MatrixGroup(3, K, [ M1, M2 ])
Matrix group of degree 3 over Cyclotomic field of order 3

julia> IR = invariant_ring(G)
Invariant ring of
Matrix group of degree 3 over Cyclotomic field of order 3
with generators
AbstractAlgebra.Generic.MatSpaceElem{nf_elem}[[0 0 1; 1 0 0; 0 1 0], [1 0 0; 0 a 0; 0 0 -a-1]]
```
"""
function invariant_ring(G::MatrixGroup)
  n = degree(G)
  action = mat_elem_type(typeof(G))[g.elm for g in gens(G)]
  return InvRing(base_ring(G), G, action)
end

#######################################################

function Base.show(io::IO, IR::InvRing)
  print(io, "Invariant ring of\n")
  print(io, group(IR), "\n")
  print(io, "with generators\n")
  print(io, action(IR))
end

function reynolds_molien_via_singular(IR::InvRing{T}) where {T <: Union{FlintRationalField, AnticNumberField}}
  if !isdefined(IR, :reynolds_singular) || !isdefined(IR, :molien_singular)
    singular_matrices = _action_singular(IR)

    rey, mol = Singular.LibFinvar.reynolds_molien(singular_matrices...)
    IR.reynolds_singular = rey
    IR.molien_singular = mol
  end
  return IR.reynolds_singular, IR.molien_singular
end

function reynolds_molien_via_singular(IR::InvRing{T}) where {T <: Union{Nemo.GaloisField, Nemo.GaloisFmpzField}}
  @assert !ismodular(IR)
  if !isdefined(IR, :reynolds_singular) || !isdefined(IR, :molien_singular)
    singular_matrices = _action_singular(IR)

    rey = Singular.LibFinvar.reynolds_molien(singular_matrices..., "")
    mol = Singular.lookup_library_symbol("Finvar", "newring")[2][:M]
    IR.reynolds_singular = rey
    IR.molien_singular = mol
  end
  return IR.reynolds_singular, IR.molien_singular
end

function reynolds_via_singular(IR::InvRing{T}) where {T <: Union{FlintRationalField, AnticNumberField, Nemo.GaloisField, Nemo.GaloisFmpzField}}
  return reynolds_molien_via_singular(IR)[1]
end

# Singular.LibFinvar.reynolds_molien does not work for finite fields which are
# not prime fields.
function reynolds_via_singular(IR::InvRing{T}) where {T <: Union{FqNmodFiniteField, FqFiniteField}}
  @assert !ismodular(IR)
  if !isdefined(IR, :reynolds_singular)
    singular_matrices = _action_singular(IR)

    rey = Singular.LibFinvar.group_reynolds(singular_matrices...)[1]
    IR.reynolds_singular = rey
  end
  return IR.reynolds_singular
end

function reynolds_operator(IR::InvRing{FldT, GrpT, T}, f::T) where {FldT, GrpT, T <: MPolyElem}
   @assert parent(f) === polynomial_ring(IR)

   rey = reynolds_via_singular(IR)
   fSing = singular_ring(polynomial_ring(IR))(f)
   fReySing = Singular.LibFinvar.evaluate_reynolds(rey, fSing)
   # fReySing is an ideal...
   @assert length(gens(fReySing)) == 1
   return polynomial_ring(IR)(gens(fReySing)[1])
end

function molien_series_via_singular(IR::InvRing{T}) where {T <: Union{FlintRationalField, AnticNumberField, Nemo.GaloisField, Nemo.GaloisFmpzField}}
  return reynolds_molien_via_singular(IR)[2]
end

function molien_series(IR::InvRing{T}) where {T <: Union{FlintRationalField, AnticNumberField}}
  mol = molien_series_via_singular(IR)
  # Singular does not build a new polynomial ring for the univariate Hilbert series
  # (how could it after all), but uses the first variable of the given ring.

  R = polynomial_ring(IR)
  K = coefficient_ring(IR)
  S, t = PolynomialRing(K, "t", cached = false)
  # Need an extra coercion here while waiting for https://github.com/Nemocas/AbstractAlgebra.jl/pull/1009
  #return to_univariate(S, R(mol[1, 1]))//to_univariate(S, R(mol[1, 2]))
  return S(to_univariate(S, R(mol[1, 1])))//S(to_univariate(S, R(mol[1, 2])))
end

function molien_series(IR::InvRing{T}) where {T <: Union{Nemo.GaloisField, Nemo.GaloisFmpzField}}
  @assert !ismodular(IR)
  mol = molien_series_via_singular(IR)

  # TODO: Write a conversion from Singular number fields to Nemo ones
  Qx, x = PolynomialRing(FlintQQ, "x", cached = false)
  K, a = number_field(Qx(Singular.n_transExt_to_spoly(Singular.modulus(coefficient_ring(parent(mol[1, 1]))))), "a", cached = false)
  R, y = PolynomialRing(K, ["y"], cached = false)
  S, t = PolynomialRing(K, "t", cached = false)

  # Need an extra coercion here while waiting for https://github.com/Nemocas/AbstractAlgebra.jl/pull/1009
  #return to_univariate(S, R(mol[1, 1]))//to_univariate(S, R(mol[1, 2]))
  return S(to_univariate(S, R(mol[1, 1])))//S(to_univariate(S, R(mol[1, 2])))
end

function invariant_basis_via_reynolds(IR::InvRing, d::Int)
  @assert d >= 0 "Dimension must be non-negative"
  @assert !ismodular(IR)
  R = polynomial_ring(IR)
  if d == 0
    return elem_type(R)[ one(R) ]
  end

  rey = reynolds_via_singular(IR)
  basisSing = Singular.LibFinvar.invariant_basis_reynolds(rey, d)
  res = Vector{elem_type(R)}()
  # [ 0 ] is not a basis, let's return [ ]
  if length(gens(basisSing)) == 1 && iszero(gens(basisSing)[1])
    return res
  end
  for f in gens(basisSing)
    push!(res, R(f))
  end
  return res
end

function invariant_basis_via_linear_algebra(IR::InvRing, d::Int)
  @assert d >= 0 "Dimension must be non-negative"
  R = polynomial_ring(IR)
  if d == 0
    return elem_type(R)[ one(R) ]
  end

  basisSing = Singular.LibFinvar.invariant_basis(d, _action_singular(IR)...)
  res = Vector{elem_type(R)}()
  # [ 0 ] is not a basis, let's return [ ]
  if length(gens(basisSing)) == 1 && iszero(gens(basisSing)[1])
    return res
  end
  for f in gens(basisSing)
    push!(res, R(f))
  end
  return res
end

function invariant_basis(IR::InvRing, d::Int)
  # TODO: Fine tune this: Depending on d and the group order it is better
  # to use "via_linear_algebra" also in the non-modular case.
  if ismodular(IR)
    return invariant_basis_via_linear_algebra(IR, d)
  else
    return invariant_basis_via_reynolds(IR, d)
  end
end

function primary_invariants_via_singular(IR::InvRing)
  if !isdefined(IR, :primary_singular)
    IR.primary_singular = Singular.LibFinvar.primary_invariants(_action_singular(IR)...)
    P = IR.primary_singular[1]
    R = polynomial_ring(IR)
    p = Vector{elem_type(R)}()
    for i = 1:ncols(P)
      push!(p, R(P[1, i]))
    end
    IR.primary = p
  end
  return IR.primary
end

#######################################################

@doc Markdown.doc"""
    primary_invariants(IR::InvRing)

Return a system of primary invariants of `IR`.

If a system of primary invariants of `IR` is already cached, return the cached system. 
Otherwise, compute and cache such a system first.

NOTE: The primary invariants are sorted by increasing degree.

# Examples
```jldoctest
julia> K, a = CyclotomicField(3, "a")
(Cyclotomic field of order 3, a)

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0])
[0   0   1]
[1   0   0]
[0   1   0]

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1])
[1   0        0]
[0   a        0]
[0   0   -a - 1]

julia> G = MatrixGroup(3, K, [ M1, M2 ])
Matrix group of degree 3 over Cyclotomic field of order 3

julia> IR = invariant_ring(G)
Invariant ring of
Matrix group of degree 3 over Cyclotomic field of order 3
with generators
AbstractAlgebra.Generic.MatSpaceElem{nf_elem}[[0 0 1; 1 0 0; 0 1 0], [1 0 0; 0 a 0; 0 0 -a-1]]

julia> primary_invariants(IR)
3-element Vector{AbstractAlgebra.Generic.MPoly{nf_elem}}:
 x[1]*x[2]*x[3]
 x[1]^3 + x[2]^3 + x[3]^3
 x[1]^3*x[2]^3 + x[1]^3*x[3]^3 + x[2]^3*x[3]^3
```
"""    
function primary_invariants(IR::InvRing)
  if !isdefined(IR, :primary)
    primary_invariants_via_singular(IR)
  end
  return copy(IR.primary)
end

function secondary_invariants_via_singular(IR::InvRing)
  if !isdefined(IR, :secondary)
    rey, mol = reynolds_molien_via_singular(IR)
    primary_invariants_via_singular(IR)
    P = IR.primary_singular
    if iszero(characteristic(coefficient_ring(IR)))
      S, IS = Singular.LibFinvar.secondary_char0(P[1], rey, mol)
    else
      S, IS = Singular.LibFinvar.secondary_charp(P...)
    end
    R = polynomial_ring(IR)
    s = Vector{elem_type(R)}()
    for i = 1:ncols(S)
      push!(s, R(S[1, i]))
    end
    is = Vector{elem_type(R)}()
    for i = 1:ncols(IS)
      push!(is, R(IS[1, i]))
    end
    IR.secondary = s
    IR.irreducible_secondary = is
  end
  return IR.secondary
end

#######################################################

@doc Markdown.doc"""
    secondary_invariants(IR::InvRing)

Return a system of secondary invariants of `IR` with respect to the currently cached system of primary invariants of `IR`
(if no system of primary invariants of `IR` is cached, compute and cache such a system first).

If a system of secondary invariants is already cached, return the cached system. 
Otherwise, compute and cache such a system first.

NOTE: The secondary invariants are sorted by increasing degree.

# Examples
```jldoctest
julia> K, a = CyclotomicField(3, "a")
(Cyclotomic field of order 3, a)

julia> M1 = matrix(K, [0 0 1; 1 0 0; 0 1 0])
[0   0   1]
[1   0   0]
[0   1   0]

julia> M2 = matrix(K, [1 0 0; 0 a 0; 0 0 -a-1])
[1   0        0]
[0   a        0]
[0   0   -a - 1]

julia> G = MatrixGroup(3, K, [ M1, M2 ])
Matrix group of degree 3 over Cyclotomic field of order 3

julia> IR = invariant_ring(G)
Invariant ring of
Matrix group of degree 3 over Cyclotomic field of order 3
with generators
AbstractAlgebra.Generic.MatSpaceElem{nf_elem}[[0 0 1; 1 0 0; 0 1 0], [1 0 0; 0 a 0; 0 0 -a-1]]

julia> secondary_invariants(IR)
2-element Vector{AbstractAlgebra.Generic.MPoly{nf_elem}}:
 1
 x[1]^6*x[3]^3 + x[1]^3*x[2]^6 + x[2]^3*x[3]^6
```
"""    
function secondary_invariants(IR::InvRing)
  if !isdefined(IR, :secondary)
    secondary_invariants_via_singular(IR)
  end
  return copy(IR.secondary)
end

function irreducible_secondary_invariants(IR::InvRing)
  if !isdefined(IR, :irreducible_secondary)
    secondary_invariants_via_singular(IR)
  end
  return copy(IR.irreducible_secondary)
end

# Doesn't belong here...
# Matrices act from the left here!
function heisenberg_group(n::Int)
  K, a = CyclotomicField(n, "a")
  M1 = zero_matrix(K, n, n)
  M1[1, n] = one(K)
  for i = 2:n
    M1[i, i - 1] = one(K)
  end

  M2 = zero_matrix(K, n, n)
  M2[1, 1] = one(K)
  for i = 2:n
    M2[i, i] = M2[i - 1, i - 1]*a
  end
  return MatrixGroup(n, K, [ M1, M2 ])
end
