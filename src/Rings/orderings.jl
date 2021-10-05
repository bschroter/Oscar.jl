module Orderings

using Oscar, Markdown
import Oscar: Ring, MPolyRing, MPolyElem, weights, IntegerUnion
export anti_diagonal, lex, degrevlex, deglex, revlex, negdeglex,
       negdegrevlex, weights, MonomialOrdering,
       ModuleOrdering, singular

abstract type AbsOrdering end

abstract type AbsGenOrdering <: AbsOrdering end

abstract type AbsModOrdering <: AbsOrdering end

"""
Ring-free monomial ordering: just the indices of the variables are given.
`T` can be a `UnitRange` to make Singular happy or any `Array` if the
  variables are not consequtive
"""
mutable struct GenOrdering{T} <: AbsGenOrdering
  vars::T
  ord::Symbol
  wgt::fmpz_mat
  function GenOrdering(u::T, s::Symbol) where {T <: AbstractVector{Int}}
    r = new{typeof(u)}()
    r.vars = u
    r.ord = s
    return r
  end
  function GenOrdering(u::T, m::fmpz_mat; ord::Symbol = :weight) where {T <: AbstractVector{Int}}
    r = new{typeof(u)}()
    @assert ncols(m) == length(u)
    r.vars = u
    r.ord = ord
    r.wgt = m
    return r
  end
end

"""
The product of `a` and `b` (`vcat` of the the matrices)
"""
mutable struct ProdOrdering <: AbsGenOrdering
  a::AbsGenOrdering
  b::AbsGenOrdering
end

Base.:*(a::AbsGenOrdering, b::AbsGenOrdering) = ProdOrdering(a, b)

#not really user facing
function ordering(a::AbstractVector{Int}, s::Union{Symbol, fmpz_mat})
  i = minimum(a)
  I = maximum(a)
  if I-i+1 == length(a) #test if variables are consecutive or not.
    return GenOrdering(i:I, s)
  end
  return GenOrdering(collect(a), s)
end

#not really user facing
function ordering(a::AbstractVector{Int}, s::Symbol, w::fmpz_mat)
  i = minimum(a)
  I = maximum(a)
  if I-i+1 == length(a)
    return GenOrdering(i:I, w, ord = s)
  end
  return GenOrdering(collect(a), w, ord = s)
end

#not really user facing, flattens a product of product orderings into an array 
function flat(a::GenOrdering)
   return [a]
end
function flat(a::ProdOrdering)
   return vcat(flat(a.a), flat(a.b))
end  

@doc Markdown.doc"""
    anti_diagonal(R::Ring, n::Int)

A square matrix with `1` on the anti-diagonal.
"""
function anti_diagonal(R::Ring, n::Int)
  a = zero_matrix(R, n, n)
  for i=1:n
    a[i, n-i+1] = one(R)
  end
  return a
end

#not user facing
function weights(a::GenOrdering)
  if a.ord == :lex || a.ord == Symbol("Singular(lp)")
    return identity_matrix(ZZ, length(a.vars))
  end
  if a.ord == :deglex
    return [matrix(ZZ, 1, length(a.vars), ones(fmpz, length(a.vars)));
            identity_matrix(ZZ, length(a.vars)-1) zero_matrix(ZZ, length(a.vars)-1, 1)]
  end
  if a.ord == :degrevlex || a.ord == Symbol("Singular(dp)")
    return [matrix(ZZ, 1, length(a.vars), ones(fmpz, length(a.vars))) ;
            zero_matrix(ZZ, length(a.vars)-1, 1) anti_diagonal(ZZ, length(a.vars)-1)]
  end              
  if a.ord == Symbol("Singular(ls)")
    return -identity_matrix(ZZ, length(a.vars))
  end
  if a.ord == Symbol("Singular(ds)")
    return [-matrix(ZZ, 1, length(a.vars), ones(fmpz, length(a.vars))) ;
            zero_matrix(ZZ, length(a.vars)-1, 1) anti_diagonal(ZZ, length(a.vars)-1)]
  end              
  if a.ord == Symbol("Singular(a)") || a.ord == Symbol("Singular(M)")
    return a.wgt
  end              
end

#not user facing
function weights(a::AbsOrdering)
  aa = flat(a)
  m = matrix(ZZ, 0, 0, [])
  for o = aa
    if typeof(o) <: GenOrdering
      w = weights(o)
      if maximum(o.vars) > ncols(m)
        m = hcat(m, zero_matrix(ZZ, nrows(m), maximum(o.vars) - ncols(m)))
      end
      mm = zero_matrix(ZZ, nrows(w), ncols(m))
      for r = 1:nrows(w)
        for c = 1:length(o.vars)
          mm[r, o.vars[c]] = w[r, c]
        end
      end
      m = vcat(m, mm)
    end
  end
  return m
end

"""
Orderings actually applied to polynomial rings (as opposed to variable indices)
"""
mutable struct MonomialOrdering{S}
  R::S
  o::AbsGenOrdering
end

#not really user facing, not exported
@doc Markdown.doc"""
    ordering(a::Vector{MPolyElem}, s::Symbol)
    ordering(a::Vector{MPolyElem}, m::fmpz_mat)
    ordering(a::Vector{MPolyElem}, s::Symbol, m::fmpz_mat)

Defines an ordering to be applied to the variables in `a`.
In the first form the symbol `s` has to be one of `:lex`, `:deglex` or `:degrevlex`.
In the second form, a weight ordering using the given matrix is used.
In the last version, the symbol if of the form `Singular(..)`.
"""
function ordering(a::AbstractVector{<:MPolyElem}, s...)
  R = parent(first(a))
  g = gens(R)
  aa = [findfirst(x -> x == y, g) for y = a]
  if nothing in aa
    error("only variables allowed")
  end
  return ordering(aa, s...)
end

@doc Markdown.doc"""
    :*(M::MonomialOrdering, N::MonomialOrdering)

For orderings on the same ring, the product ordering obtained by concatenation
of the weight matrix.
"""
function Base.:*(M::MonomialOrdering, N::MonomialOrdering)
  M.R == N.R || error("wrong rings")
  return MonomialOrdering(M.R, M.o*N.o)
end

function Base.show(io::IO, M::MonomialOrdering)
  a = flat(M.o)
  if length(a) > 1
    print(io, "Product ordering: ")
    for i=1:length(a)-1
      show(io, M.R, a[i])
      print(io, " \\times ")
    end
  end
  show(io, M.R, a[end])
end

function Base.show(io::IO, R::MPolyRing, o::GenOrdering)
  if o.ord == :weight
    print(io, "weight($(gens(R)[o.vars]) via $(o.wgt))")
  else
    print(io, "$(String(o.ord))($(gens(R)[o.vars]))")
  end
end

@doc Markdown.doc"""
    lex(v::AbstractVector{<:MPolyElem}) -> MonomialOrdering

Defines the `lex` (lexicographic) ordering on the variables given.
"""
function lex(v::AbstractVector{<:MPolyElem})
  return MonomialOrdering(parent(first(v)), ordering(v, :lex))
end
@doc Markdown.doc"""
    deglex(v::AbstractVector{<:MPolyElem}) -> MonomialOrdering

Defines the `deglex` ordering on the variables given.
"""
function deglex(v::AbstractVector{<:MPolyElem})
  return MonomialOrdering(parent(first(v)), ordering(v, :deglex))
end
@doc Markdown.doc"""
    degrevlex(v::AbstractVector{<:MPolyElem}) -> MonomialOrdering

Defines the `degrevlex` ordering on the variables given.
"""
function degrevlex(v::AbstractVector{<:MPolyElem})
  return MonomialOrdering(parent(first(v)), ordering(v, :degrevlex))
end
@doc Markdown.doc"""
    revlex(v::AbstractVector{<:MPolyElem}) -> MonomialOrdering

Defines the `revlex` ordering on the variables given.
"""
function revlex(v::AbstractVector{<:MPolyElem})
  return MonomialOrdering(parent(first(v)), ordering(v, :revlex))
end
@doc Markdown.doc"""
    negdegrevlex(v::AbstractVector{<:MPolyElem}) -> MonomialOrdering

Defines the `negdegrevlex` ordering on the variables given.
"""
function negdegrevlex(v::AbstractVector{<:MPolyElem})
  return MonomialOrdering(parent(first(v)), ordering(v, :negdegrevlex))
end
@doc Markdown.doc"""
    negdeglex(v::AbstractVector{<:MPolyElem}) -> MonomialOrdering

Defines the `negdeglex` ordering on the variables given.
"""
function negdeglex(v::AbstractVector{<:MPolyElem})
  return MonomialOrdering(parent(first(v)), ordering(v, :negdeglex))
end

@doc Markdown.doc"""
    singular(ord::Symbol, v::AbstractVector{<:MPolyElem}) -> MonomialOrdering

Defines an ordering given in terms of Singular primitives on the variables given.
`ord` can be one of `:lp`, `:ls`, `:dp`, `:ds`.
"""
function singular(ord::Symbol, v::AbstractVector{<:MPolyElem})
  return MonomialOrdering(parent(first(v)), ordering(v, Symbol("Singular($(string(ord)))")))
end

@doc Markdown.doc"""
    singular(ord::Symbol, v::AbstractVector{<:MPolyElem}, w::AbstractMatrix{<:IntegerUnion}) -> MonomialOrdering

Defines an ordering given in terms of Singular weight ordering (`M`) with the
matrix given. `ord` has to be `:M` here.
"""
function singular(ord::Symbol, v::AbstractVector{<:MPolyElem}, w::AbstractMatrix{<:IntegerUnion})
  @assert ord == :M
  W = matrix(ZZ, size(w, 1), size(w, 2), w)
  return MonomialOrdering(parent(first(v)), ordering(v, Symbol("Singular($(string(ord)))"), W))
end

@doc Markdown.doc"""
    singular(ord::Symbol, v::AbstractVector{<:MPolyElem}, w::AbstractVector{<:IntegerUnion}) -> MonomialOrdering

Defines an ordering given in terms of Singular weight ordering (`a`) with the
weights given. `ord` has to be `:a` here. The weights will be supplemented by
`0`.
"""
function singular(ord::Symbol, v::AbstractVector{<:MPolyElem}, w::AbstractVector{<:IntegerUnion})
  @assert ord == :a
  W = map(fmpz, w)
  while length(v) > length(W)
    push!(W, 0)
  end

  return MonomialOrdering(parent(first(v)), ordering(v, Symbol("Singular($(string(ord)))"), matrix(ZZ, 1, length(W), W)))

end

@doc Markdown.doc"""
    weights(M::MonomialOrdering)
 
Compute a corresponding weight matrix for the given ordering.
"""
function weights(M::MonomialOrdering)
  return weights(M.o)
end

@doc Markdown.doc"""
    simplify(M::MonomialOrdering) -> MonomialOrdering

Compute a weight ordering with a unique weight matrix.    
"""
function Hecke.simplify(M::MonomialOrdering)
  ww = simplify_weight_matrix(M.o)
  return MonomialOrdering(M.R, ordering(1:ncols(ww), ww))
end

function simplify_weight_matrix(M::AbsOrdering)
  w = weights(M)
  ww = matrix(ZZ, 0, ncols(w), [])
  for i=1:nrows(w)
    if iszero_row(w, i)
      continue
    end
    nw = w[i, :]
    c = content(nw)
    if c != 1
      nw = divexact(nw, c)
    end
    for j=1:nrows(ww)
      h = findfirst(x->ww[j, x] != 0, 1:ncols(w))
      if nw[1, h] != 0
        nw = abs(ww[j, h])*nw - sign(ww[j, h])*nw[1, h]*ww[j, :]
      end
    end
    if !iszero(nw)
      c = content(nw)
      if !isone(c)
        nw = divexact(nw, c)
      end
      ww = vcat(ww, nw)
    end
  end
  return ww
end

import Base.==
function ==(M::MonomialOrdering, N::MonomialOrdering)
  return Hecke.simplify(M).o.wgt == Hecke.simplify(N).o.wgt
end

function Base.hash(M::MonomialOrdering, u::UInt)
  return hash(Hecke.simplify(M).o.wgt, u)
end

###################################################

# Module orderings (not module Orderings)

mutable struct ModOrdering{T} <: AbsModOrdering
   gens::T
   ord::Symbol
   function ModOrdering(u::T, s::Symbol) where {T <: AbstractVector{Int}}
     r = new{T}()
     r.gens = u
     r.ord = s
     return r
   end
end

mutable struct ModuleOrdering{S}
   M::S
   o::AbsOrdering # must allow gen*mon or mon*gen product ordering
end

mutable struct ModProdOrdering <: AbsModOrdering
   a::AbsOrdering
   b::AbsOrdering
 end

Base.:*(a::AbsGenOrdering, b::AbsModOrdering) = ModProdOrdering(a, b)

Base.:*(a::AbsModOrdering, b::AbsGenOrdering) = ModProdOrdering(a, b)

function module_ordering(a::AbstractVector{Int}, s::Symbol)
   i = minimum(a)
   I = maximum(a)
   if I-i+1 == length(a) #test if variables are consecutive or not.
     return ModOrdering(i:I, s)
   end
   return ModOrdering(collect(a), s)
 end

function ordering(a::AbstractVector{<:AbstractAlgebra.ModuleElem}, s...)
   R = parent(first(a))
   g = gens(R)
   aa = [findfirst(x -> x == y, g) for y = a]
   if nothing in aa
     error("only generators allowed")
   end
   return module_ordering(aa, s...)
 end

function lex(v::AbstractVector{<:AbstractAlgebra.ModuleElem})
   return ModuleOrdering(parent(first(v)), ordering(v, :lex))
end

function Base.:*(M::ModuleOrdering, N::MonomialOrdering)
   base_ring(M.M) == N.R || error("wrong rings")
   return ModuleOrdering(M.M, M.o*N.o)
end

function Base.:*(M::MonomialOrdering, N::ModuleOrdering)
   base_ring(N.M) == M.R || error("wrong rings")
   return ModuleOrdering(N.M, M.o*N.o)
end

function flat(a::ModOrdering)
   return [a]
end
function flat(a::ModProdOrdering)
   return vcat(flat(a.a), flat(a.b))
end

function max_used_variable(st::Int, o::GenOrdering)
   g = o.vars
   mi = minimum(g)
   ma = maximum(g)
   if mi == st && length(g) + st == ma+1
      return ma+1
   else
      return 0
   end
end

function max_used_variable(st::Int, o::ModOrdering)
   return -1
end

end  # module Orderings

###################################################

# Some isless functions for orderings:
# _isless_:ord(f, k, l) returns true if the k-th term is lower than the l-th
# term of f in the ordering :ord.

function _isless_lex(f::MPolyElem, k::Int, l::Int)
   n = nvars(parent(f))
   for i = 1:n
     ek = exponent(f, k, i)
     el = exponent(f, l, i)
     if ek == el
       continue
     elseif ek > el
       return false
     else
       return true
     end
   end
   return false
 end
 
 function _isless_neglex(f::MPolyElem, k::Int, l::Int)
   n = nvars(parent(f))
   for i = 1:n
     ek = exponent(f, k, i)
     el = exponent(f, l, i)
     if ek == el
       continue
     elseif ek < el
       return false
     else
       return true
     end
   end
   return false
 end
 
 function _isless_revlex(f::MPolyElem, k::Int, l::Int)
   n = nvars(parent(f))
   for i = n:-1:1
     ek = exponent(f, k, i)
     el = exponent(f, l, i)
     if ek == el
       continue
     elseif ek > el
       return false
     else
       return true
     end
   end
   return false
 end
 
 function _isless_negrevlex(f::MPolyElem, k::Int, l::Int)
   n = nvars(parent(f))
   for i = n:-1:1
     ek = exponent(f, k, i)
     el = exponent(f, l, i)
     if ek == el
       continue
     elseif ek < el
       return false
     else
       return true
     end
   end
   return false
 end
 
 function _isless_deglex(f::MPolyElem, k::Int, l::Int)
   tdk = total_degree(term(f, k))
   tdl = total_degree(term(f, l))
   if tdk < tdl
     return true
   elseif tdk > tdl
     return false
   end
   return _isless_lex(f, k, l)
 end
 
 function _isless_degrevlex(f::MPolyElem, k::Int, l::Int)
   tdk = total_degree(term(f, k))
   tdl = total_degree(term(f, l))
   if tdk < tdl
     return true
   elseif tdk > tdl
     return false
   end
   return _isless_negrevlex(f, k, l)
 end
 
 function _isless_negdeglex(f::MPolyElem, k::Int, l::Int)
   tdk = total_degree(term(f, k))
   tdl = total_degree(term(f, l))
   if tdk > tdl
     return true
   elseif tdk < tdl
     return false
   end
   return _isless_lex(f, k, l)
 end
 
 function _isless_negdegrevlex(f::MPolyElem, k::Int, l::Int)
   tdk = total_degree(term(f, k))
   tdl = total_degree(term(f, l))
   if tdk > tdl
     return true
   elseif tdk < tdl
     return false
   end
   return _isless_negrevlex(f, k, l)
 end
 
 # Returns the degree of the k-th term of f weighted by w,
 # that is deg(x^a) = w_1a_1 + ... + w_na_n.
 # No sanity checks are performed!
 function weighted_degree(f::MPolyElem, k::Int, w::Vector{Int})
   ek = exponent_vector(f, k)
   return dot(ek, w)
 end

 function _isless_weightlex(f::MPolyElem, k::Int, l::Int, w::Vector{Int})
   dk = weighted_degree(f, k, w)
   dl = weighted_degree(f, l, w)
   if dk < dl
     return true
   elseif dk > dl
     return false
   end
   return _isless_lex(f, k, l)
 end
 
 function _isless_weightrevlex(f::MPolyElem, k::Int, l::Int, w::Vector{Int})
   dk = weighted_degree(f, k, w)
   dl = weighted_degree(f, l, w)
   if dk < dl
     return true
   elseif dk > dl
     return false
   end
   return _isless_negrevlex(f, k, l)
 end
 
 function _isless_weightneglex(f::MPolyElem, k::Int, l::Int, w::Vector{Int})
   dk = weighted_degree(f, k, w)
   dl = weighted_degree(f, l, w)
   if dk < dl
     return true
   elseif dk > dl
     return false
   end
   return _isless_lex(f, k, l)
 end
 
 function _isless_weightnegrevlex(f::MPolyElem, k::Int, l::Int, w::Vector{Int})
   dk = weighted_degree(f, k, w)
   dl = weighted_degree(f, l, w)
   if dk > dl
     return true
   elseif dk < dl
     return false
   end
   return _isless_negrevlex(f, k, l)
 end
 
 function _isless_matrix(f::MPolyElem, k::Int, l::Int, M::Union{ Matrix{T}, MatElem{T} }) where T
   ek = exponent_vector(f, k)
   el = exponent_vector(f, l)
   n = nvars(parent(f))
   for i = 1:size(M, 1)
     eki = sum( M[i, j]*ek[j] for j = 1:n )
     eli = sum( M[i, j]*el[j] for j = 1:n )
     if eki == eli
       continue
     elseif eki > eli
       return false
     else
       return true
     end
   end
   return false
 end
 
 function _perm_of_terms(f::MPolyElem, ord_lt::Function)
   p = collect(1:length(f))
   sort!(p, lt = (k, l) -> ord_lt(f, k, l), rev = true)
   return p
 end
 
 # Requiring R for consistence with the other lt_from_ordering functions
 function lt_from_ordering(::MPolyRing, ord::Symbol)
   if ord == :lex || ord == :lp
     return _isless_lex
   elseif ord == :revlex || ord == :rp
     return _isless_revlex
   elseif ord == :deglex || ord == :Dp
     return _isless_deglex
   elseif ord == :degrevlex || ord == :dp
     return _isless_degrevlex
   elseif ord == :neglex || ord == :ls
     return _isless_neglex
   elseif ord == :negrevlex || ord == :rs
     return _isless_negrevlex
   elseif ord == :negdeglex || ord == :Ds
     return _isless_negdeglex
   elseif ord == :negdegrevlex || ord == :ds
     return _isless_negdegrevlex
   else
     error("Ordering $ord not available")
   end
 end
 
 function lt_from_ordering(R::MPolyRing, ord::Symbol, w::Vector{Int})
   @assert length(w) == nvars(R) "Number of weights has to match number of variables"
 
   if ord == :wlex || ord == :Wp
     @assert all(x -> x > 0, w) "Weights have to be positive"
     return (f, k, l) -> _isless_weightlex(f, k, l, w)
   elseif ord == :wrevlex || ord == :wp
     @assert all(x -> x > 0, w) "Weights have to be positive"
     return (f, k, l) -> _isless_weightrevlex(f, k, l, w)
   elseif ord == :wneglex || ord == :Ws
     @assert !iszero(w[1]) "First weight must not be 0"
     return (f, k, l) -> _isless_weightneglex(f, k, l, w)
   elseif ord == :wnegrevlex || ord == :ws
     @assert !iszero(w[1]) "First weight must not be 0"
     return (f, k, l) -> _isless_weightnegrevlex(f, k, l, w)
   else
     error("Ordering $ord not available")
   end
 end
 
 function lt_from_ordering(R::MPolyRing, M::Union{ Matrix{T}, MatElem{T} }) where T
   @assert size(M, 2) == nvars(R) "Matrix dimensions have to match number of variables"
 
   return (f, k, l) -> _isless_matrix(f, k, l, M)
 end