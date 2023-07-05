#####################################################
# 1: Adjust the description for the model
#####################################################

@doc raw"""
    set_description(t::AbstractFTheoryModel, description::String)

Set a description for a model.

```jldoctest
julia> t = literature_model(arxiv_id = "1109.3454", equation = "3.1")
Global Tate model over a not fully specified base -- SU(5)xU(1) restricted Tate model based on arXiv paper 1109.3454 Eq. (3.1)

julia> set_description(t, "An SU(5)xU(1) GUT-model")

julia> t
Global Tate model over a not fully specified base -- An SU(5)xU(1) GUT-model based on arXiv paper 1109.3454 Eq. (3.1)
```
"""
function set_description(t::AbstractFTheoryModel, description::String)
  set_attribute!(t, :description => description)
end


#####################################################
# 2: Add a resolution
#####################################################

@doc raw"""
    add_resolution(t::AbstractFTheoryModel, centers::Vector{Vector{String}}, exceptionals::Vector{String})

Add a known resolution for a model.

```jldoctest
julia> t = literature_model(arxiv_id = "1109.3454", equation = "3.1")
Global Tate model over a not fully specified base -- SU(5)xU(1) restricted Tate model based on arXiv paper 1109.3454 Eq. (3.1)

julia> add_resolution(t, [["x", "y"], ["y", "s", "w"], ["s", "e4"], ["s", "e3"], ["s", "e1"]], ["s", "w", "e3", "e1", "e2"])

julia> length(resolutions(t))
2
```
"""
function add_resolution(t::AbstractFTheoryModel, centers::Vector{Vector{String}}, exceptionals::Vector{String})
  @req length(exceptionals) == length(centers) "Number of exceptionals must match number of centers"

  resolution = [centers, exceptionals]
  if has_attribute(t, :resolutions)
    known_resolutions = resolutions(t)
    if (resolution in known_resolutions) == false
      push!(known_resolutions, resolution)
      set_attribute!(t, :resolutions => known_resolutions)
    end
  else
    set_attribute!(t, :resolutions => [resolution])
  end
end


#####################################################
# 3: Resolve a model with a known resolution
#####################################################

@doc raw"""
    resolve(t::AbstractFTheoryModel, index::Int)

Resolve a model with the index-th resolution that is known.

Careful: Currently, this assumes that all blowups are toric blowups.
We hope to remove this requirement in the near future.

```jldoctest
julia> t = literature_model(arxiv_id = "1109.3454", equation = "3.1")
Global Tate model over a not fully specified base -- SU(5)xU(1) restricted Tate model based on arXiv paper 1109.3454 Eq. (3.1)

julia> v = resolve(t, 1)
Scheme of a toric variety with fan spanned by RayVector{QQFieldElem}[[1, 0, 0, 0, 0, -2, -3], [0, 0, 0, 1, 0, -2, -3], [0, 0, 0, 0, 1, -2, -3], [0, 1, 0, 0, 0, -2, -3], [0, 0, 1, 0, 0, -2, -3], [0, 0, 0, 0, 0, 1, 0], [0, 0, 0, 0, 0, 0, 1], [0, 0, 0, 0, 0, -1, -3//2], [0, 0, 1, 0, 0, -1, -2], [0, 0, 1, 0, 0, -1, -1], [0, 0, 1, 0, 0, 0, -1], [0, 0, 1, 0, 0, 0, 0], [0, 0, 0, 0, 0, 1, 1]]

julia> cox_ring(v)
Multivariate polynomial ring in 13 variables over QQ graded by
  a1 -> [0 0 0 0 0 0]
  a21 -> [0 0 0 0 0 0]
  a32 -> [0 0 0 0 0 0]
  a43 -> [0 0 0 0 0 0]
  w -> [1 0 0 0 0 0]
  x -> [0 1 0 0 0 0]
  y -> [0 0 1 0 0 0]
  z -> [0 0 0 1 0 0]
  e1 -> [0 0 0 0 1 0]
  e4 -> [0 0 0 0 0 1]
  e2 -> [-1 -1 1 -1 -1 0]
  e3 -> [0 1 -1 1 0 -1]
  s -> [2 -1 0 2 1 1]
```
"""
function resolve(t::AbstractFTheoryModel, index::Int)
  @req has_attribute(t, :resolutions) "No resolutions known for this model"
  @req index > 0 "The resolution must be specified by a non-negative integer"
  @req index <= length(resolutions(t)) "The resolution must be specified by an integer that is not larger than the number of known resolutions"
  
  # Gather information for resolution
  centers, exceptionals = resolutions(t)[index]
  nr_blowups = length(centers)
  
  # Is this a sequence of toric blowups? (To be extended with @HechtiDerLachs and ToricSchemes).
  resolved_ambient_space = underlying_toric_variety(ambient_space(t))
  R, gR = PolynomialRing(QQ, vcat([string(g) for g in gens(cox_ring(resolved_ambient_space))], exceptionals))
  for center in centers
    @req all(x -> x in gR, [eval_poly(p, R) for p in center]) "Non-toric blowup currently not supported"
  end
  
  # Perform resolution
  for k in 1:nr_blowups
    S = cox_ring(resolved_ambient_space)
    resolved_ambient_space = blow_up(resolved_ambient_space, ideal([eval_poly(g, S) for g in centers[k]]); coordinate_name = exceptionals[k], set_attributes = true)
  end
  return toric_covered_scheme(resolved_ambient_space)
end
