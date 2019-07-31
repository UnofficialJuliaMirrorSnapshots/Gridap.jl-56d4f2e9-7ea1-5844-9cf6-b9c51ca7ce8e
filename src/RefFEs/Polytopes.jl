module Polytopes

using Gridap
using Gridap.Helpers
using StaticArrays
using Base.Cartesian
using LinearAlgebra

using Combinatorics

export Polytope
export NodesArray
export NFace
export HEX_AXIS, TET_AXIS
export num_nfaces
export facet_normals

# Module constants

const HEX_AXIS = 1
const TET_AXIS = 2

# Concrete structs and their pubic API

# const Point{D,Int} = SVector{D,Int64} where D
# @santiagobadia : Probably add Type of coordinates in Point{D} (@fverdugo: Now we have Point{D,T})
# @santiagobadia : I will re-think the NodeArray when I have at my disposal
# the geomap on n-faces, etc. And a clearer definition of the mesh object
# to discuss with @fverdugo

"""
n-face of the polytope, i.e., any polytope of lower dimension `N` representing
its boundary and the polytope itself (for `N` equal to the space dimension `D`)
"""
struct NFace{D}
  anchor::Point{D,Int}
  extrusion::Point{D,Int}
end

"""
Aggregation of all n-faces that compose the polytope boundary and the polytope
itself, the classification of n-faces with respect to their dimension and type
"""
struct Polytope{D}
  extrusion::Point{D,Int}
  nfaces::Vector{NFace}
  nf_nfs::Vector{Vector{Int64}}
  nf_dim::Vector{Vector{UnitRange{Int64}}}
end

"""
Constructs a `Polytope` given the type of extrusion, i.e., HEX_AXIS (=1) for "hex" extrusion
and TET_AXIS (=2) for "tet" extrusion
"""
function Polytope(extrusion::Vararg{Int,N}) where N
  return Polytope(Point{N,Int}(extrusion))
end

function Polytope(extrusion::NTuple{N,Int}) where N
  return Polytope(extrusion...)
end

function Polytope(extrusion::Point{D,Int}) where D
  zerop = Point{D,Int}(zeros(Int64,D))
  pol_nfs_dim = polytopenfaces(zerop, extrusion)
  pol_nfs = pol_nfs_dim[1]; pol_dim = pol_nfs_dim[2]
  nfs_id = Dict(nf => i for (i,nf) in enumerate(pol_nfs))
  nf_nfs_dim = polytopemesh(pol_nfs, nfs_id)
  nf_nfs = nf_nfs_dim[1]; nf_dim = nf_nfs_dim[2]
  Polytope{D}(extrusion, pol_nfs, nf_nfs, nf_dim)
end

#@fverdugo add here a public API to access the polytope info instead
# of using the struct fields directly as it is currently done
# in some places of the code.

"""
Returns number of nfaces of dimension dim
"""
function num_nfaces(polytope::Polytope, dim::Integer)
  n = length(polytope.nf_dim)
  k = 0
  for nface in 1:n
    d = length(polytope.nf_dim[nface])-1
    if d == dim
      k +=1
    end
  end
  k
end

"""
Array of nodes for a given polytope and order
"""
struct NodesArray{D}
  coordinates::Vector{Point{D,Float64}}
  nfacenodes::Array{Array{Int64,1},1}
  closurenfacenodes::Array{Array{Int64,1},1}
  # @santiagobadia : To be changed to points
end

"""
Creates an array of nodes `NodesArray` for a given polytope and the order per
dimension.
"""
# @santiagobadia : TO BE REMOVED
function NodesArray(polytope::Polytope, orders::Array{Int64,1})
  @notimplementedif any([ t != HEX_AXIS for t in polytope.extrusion.array])
  closurenfacenodes = [
  createnodes(polytope.nfaces[i],
  orders) for i=1:length(polytope.nfaces)]
  nfacenodes = [
  createnodes(polytope.nfaces[i],orders,
  isopen=true) for i=1:length(polytope.nfaces)]
  D = length(orders)
  coords = [
  nodescoordinates(orders[i], nodestype="Equispaced") for i=1:D]
  npoints =  prod(ntuple(i -> length(coords[i]), D))
  points = Vector{Point{D,Float64}}(undef,npoints)
  cid = ntuple(i -> 1:length(coords[i]), D)
  cid = CartesianIndices(cid)
  tpcoor = j -> [ coords[i][j[i]] for i ∈ 1:D]
  for (i,j) ∈ enumerate(cid)
    points[i] = tpcoor(Tuple(j))
  end
  NodesArray(points, nfacenodes, closurenfacenodes)
end


# Helpers

# @fverdugo Following the style in julia.Base, I would name with a leading
# underscore all helper functions that are not exposed to the public API

nfdim(a::Point{D,Int}) where D = sum([a[i] > 0 ? 1 : 0 for i =1:D ])

"""
Generates the array of n-faces of a polytope
"""
function polytopenfaces(anchor::Point{D,Int}, extrusion::Point{D,Int}) where D
  dnf = nfdim(extrusion)
  zerop = Point{D,Int}(zeros(Int64,D))
  nf_nfs = []
  nf_nfs = nfaceboundary!(anchor, zerop, extrusion, true, nf_nfs)
  [sort!(nf_nfs, by = x -> x.anchor[i]) for i=1:length(extrusion)]
  [sort!(nf_nfs, by = x -> x.extrusion[i]) for i=1:length(extrusion)]
  [sort!(nf_nfs, by = x -> sum(x.extrusion))]
  numnfs = length(nf_nfs)
  nfsdim = [nfdim(nf_nfs[i].extrusion) for i=1:numnfs]
  dimnfs = Array{UnitRange{Int64},1}(undef,dnf+1)
  dim=0; i=1
  for iface=1:numnfs
    if (nfsdim[iface]>dim)
      # global dim; # global i
      dim+=1
      dimnfs[dim]=i:iface-1
      i=iface
    end
  end
  dimnfs[dnf+1]=numnfs:numnfs
  return [nf_nfs,dimnfs]
end

# Generates the reference polytopes for all n-faces (undef for vertices)
function _nface_ref_polytopes(p::Polytope)
  function _eliminate_zeros(a)
    b = Int[]
    for m in a
      if (m !=0)
        push!(b,m)
      end
    end
    return Tuple(b)
  end
  nf_ref_p = Vector{Polytope}(undef,length(p.nfaces))
  ref_nf_ps = Polytope[]
  for (i_nf,nf) in enumerate(p.nfaces)
    r_ext = _eliminate_zeros(nf.extrusion)
    if r_ext != ()
      k = 0
      for (i_p,ref_p) in enumerate(ref_nf_ps)
        if r_ext == ref_p.extrusion
          k = i_p
          nf_ref_p[i_nf] = ref_p
        end
      end
      if k == 0
        ref_p = Polytope(r_ext)
        push!(ref_nf_ps,ref_p)
        k = length(ref_nf_ps)+1
        nf_ref_p[i_nf] = ref_p
      end
    end
  end
  return nf_ref_p
end

"""
Provides for all n-faces of a polytope the d-faces for 0 <= d <n on its
boundary (e.g., given a face, it provides the set of edges and corners on its
boundary) using the global n-face numbering of the base polytope
"""
function polytopemesh(nfaces::Vector{NFace{D}}, nfaceid::Dict) where D
  num_nfs = length(nfaces)
  nfnfs = Vector{Vector{Int64}}(undef,num_nfs)
  nfnfs_dim = Vector{Vector{UnitRange{Int64}}}(undef,num_nfs)
  for (inf,nf) in enumerate(nfaces)
    nfs_dim_nf = polytopenfaces(nf.anchor, nf.extrusion)
    nf_nfs = nfs_dim_nf[1]; dimnfs = nfs_dim_nf[2]
    nfnfs[inf] = [ get(nfaceid,nf,nf) for nf in nf_nfs ]
    nfnfs_dim[inf] = dimnfs
  end
  return [nfnfs, nfnfs_dim]
end

"""
Generates the list of n-face of a polytope the d-faces for 0 <= d <n on its
boundary
"""
function nfaceboundary!(
  anchor::Point{D,Int}, extrusion::Point{D,Int},
  extend::Point{D,Int}, isanchor::Bool, list) where D
  newext = extend
  list = [list..., NFace{D}(anchor, extrusion)]
  for i = 1:D
    curex = newext[i]
    if (curex > 0) # Perform extension
      func1 = (j -> j==i ? 0 : newext[j])
      newext = Point{D,Int}([func1(i) for i=1:D])
      func2 = (j -> j==i ? 1 : 0)
      edim = Point{D,Int}([func2(i) for i=1:D])
      func3 = (j -> j >= i ? anchor[j] : 0 )
      tetp = Point{D,Int}([func3(i) for i=1:D]) + edim
      if (curex == 1) # Quad extension
        list = nfaceboundary!(anchor+edim, extrusion, newext, false, list)
      elseif (isanchor)
        list = nfaceboundary!(tetp, extrusion, newext, false, list)
      end
      list = nfaceboundary!(anchor, extrusion+edim*curex, newext, false, list)
    end
  end
  return list
end

"""
It provides for every df-face in the polytope all its dt-faces
"""
# @santiagobadia : New method required by @fverdugo
function _dimfrom_fs_dimto_fs(p::Polytope, dim_from::Int, dim_to::Int)
  @assert dim_to <= dim_from
  dim_from +=1; dim_to +=1
  dffs_r = p.nf_dim[end][dim_from]
  dffs_dtfs = Vector{Vector{Int}}(undef, dffs_r[end]-dffs_r[1]+1)
  offs = p.nf_dim[end][dim_to][1]-1
  for (i_dff, dff) in enumerate(dffs_r)
    dff_nfs = p.nf_nfs[dff]
    dff_dtfs_r = p.nf_dim[dff][dim_to]
    dff_dtfs = dff_nfs[dff_dtfs_r]
    dffs_dtfs[i_dff] = dff_dtfs .- offs
    # @santiagobadia : With or without offset ?
  end
  return dffs_dtfs
end

"""
It generates all the admissible permutations of nodes that lead to an
admissible polytope
"""
function generate_admissible_permutations(p::Polytope)
  p_dims = length(p.extrusion)
  p_vs = Gridap.Polytopes._dimfrom_fs_dimto_fs(p,p_dims,0)
  vs = p.nfaces[p_vs...]
  num_vs = length(vs)
  ext = p.extrusion
  l = [i  for i in 1:num_vs]
  # @santiagobadia : Here we have to decide how we want this info stored
  permuted_polytopes = Vector{Int}[]
  for c in Combinatorics.permutations(l,p_dims+1)
    admissible_polytope = true
    c1 = vs[c[1]].anchor
    for j in 2:p_dims+1
      c2 = vs[c[j]].anchor
      if ( !_are_nodes_connected(c1,c2,ext) )
        admissible_polytope = false
      end
    end
    if (admissible_polytope)
      push!(permuted_polytopes,c)
    end
  end
  return permuted_polytopes
end

"""
Auxiliary function that determines whether two nodes are connected
"""
function _are_nodes_connected(c1, c2, ext)
  sp_dims = length(c1)
  d = zeros(length(c1))
  for i in 1:length(d)
    d[i] = c2[i]-c1[i]
  end
  dn = sum(d.*d)
  connected = false
  if (dn == 1)
    connected = true
  else
    k = 0
    for j in 1:sp_dims
      if (ext[j] == 2)
        if (c1[j] == 1 || c2[j] == 1)
          k = j
        end
      end
    end
    for l in 1:k
      d[l] = 0
    end
    dn = sum(d.*d)
    if (dn == 0)
      connected = true
    end
  end
  return connected
end

"""
It generates the set of nodes (its coordinates) in the interior of an n-face,
for a given order. The node coordinates are the ones for a equispace case.
"""
function equidistant_interior_nodes_coordinates(p::Polytope{D}, order) where D
  ns = _interior_nodes_int_coords(p, _order)
  return ns_float = _interior_nodes_int_to_real_coords(ns,_order)
end

# It generates the set of nodes (its coordinates) in the interior of an n-face,
# for a given order. The node coordinates are `Int` and from 0 to `order` per
# direction
function _interior_nodes_int_coords(p::Polytope{D}, order) where D
  ext = p.extrusion
  _ord = [order...]
  verts = Point{D,Int}[]
  coor = zeros(Int,D)
  _generate_nodes!(D, p.extrusion, _ord, coor, verts)
  return verts
end

# Auxiliary private recursive function to implement _interior_nodes_int_coords
function _generate_nodes!(dim, ext, order, coor, verts)
  ncoo = copy(coor)
  nord = copy(order)
  for i in 1:order[dim]-1
    ncoo[dim] = i
    if dim > 1
      if (ext[dim] == TET_AXIS ) nord.-= 1 end
      _generate_nodes!(dim-1, ext, nord, ncoo, verts)
    else
      push!(verts,Point(ncoo...))
    end
  end
end

# Transforms the int coordinates to float coordinates
function _interior_nodes_int_to_real_coords(nodes, order)
  if length(nodes) > 0
    dim = length(nodes[1])
    cs_float = Point{dim,Float64}[]
    cs = zeros(Float64,dim)
    for cs_int in nodes
      for i in 1:dim
        cs[i] = cs_int[i]/order[i]
      end
      push!(cs_float,Point{dim,Float64}(cs))
    end
  else
    cs_float = Point{0,Float64}[]
  end
  return cs_float
end

"""
It generates the list of coordinates of all vertices in the polytope. It is
assumed that the polytope has the bounding box [0,1]**dim
"""
function vertices_coordinates(p::Polytope{D}) where D
  vs = _dimfrom_fs_dimto_fs(p, D, 0)[1]
  vcs = Point{D,Float64}[]
  for i in 1:length(vs)
    cs = convert(Vector{Float64}, [p.nfaces[vs[i]].anchor...])
    push!(vcs,cs)
  end
  return vcs
end

"""
It generates the outwards normals of the facets of a polytope
"""
function facet_normals(p::Polytope{D}) where D
  nf_vs = _dimfrom_fs_dimto_fs(p,D-1,0)
  vs = vertices_coordinates(p)
  f_ns = Point{D,Float64}[]
  f_os = Int[]
  for i_f in 1:length(p.nf_dim[end][end-1])
    # @santiagobadia : we are allocating memory here but this
    # part of the code is not a computationally intensive one
    n, f_o = _facet_normal(p,nf_vs,vs,i_f)
    push!(f_ns,Point{D,Float64}(n))
    push!(f_os,f_o)
  end
  return f_ns, f_os
end

function _facet_normal(p::Polytope{D},nf_vs,vs,i_f) where D
  if (length(p.extrusion) > 1)
    v = Float64[]
    for i = 2:length(nf_vs[i_f])
      vi = vs[nf_vs[i_f][i]] - vs[nf_vs[i_f][1]]
      push!(v,vi...)
    end
    n = nullspace(transpose(reshape(v,D,length(nf_vs[i_f])-1)))
    # v1 = vs[nf_vs[i_f][2]] - vs[nf_vs[i_f][1]]
    # v2 = vs[nf_vs[i_f][3]] - vs[nf_vs[i_f][1]]
    # n = LinearAlgebra.cross([v1...],[v2...])
    n = n.*1/sqrt(dot(n,n))
    ext_v = _vertex_not_in_facet(p,i_f,nf_vs)
    v3 = vs[nf_vs[i_f][1]] - vs[ext_v]
    f_or = 1
    if dot(v3,n) < 0.0
      n *= -1
      f_or = -1
    end
  elseif (length(p.extrusion) == 1)
    ext_v = _vertex_not_in_facet(p,i_f,nf_vs)
    n = vs[nf_vs[i_f][1]] - vs[ext_v]
    n = n.*1/dot(n,n)
    f_or = 1
  else
    error("O-dim polytopes do not have properly define outward facet normals")
  end
  return n, f_or
end

function _vertex_not_in_facet(p,i_f,nf_vs)
  for i in p.nf_dim[end][1]
    is_in_f = false
    for j in nf_vs[i_f]
      if i == j
        is_in_f = true
        break
      end
    end
    if !is_in_f
      return i; break
    end
  end
end

# @santiagobadia : The rest is waiting for a geomap

# Create list of nface nodes with polytope indexing
function createnodes(nface::NFace,orders; isopen::Bool=false)
  spdims=length(nface.extrusion)
  @assert spdims == length(orders) "nface and orders dim must be identical"
  perms=nfaceperms(nface)
  p=perms[1]; pinv=perms[2]
  ordnf=orders[pinv]; ordp1=ordnf.+((isopen) ? d=-1 : d=1)
  A = Array{Array{Int64,1}}(undef,ordp1...)
  cartesianindexmatrix!(A)
  A = hcat(reshape(A, length(A))...)'
  if (isopen) A.+=1 end
  B = Array{Int64,2}(undef,prod(ordp1),spdims)
  for i=1:spdims
    if (p[i]==0) B[:,i].=nface.anchor[i]*orders[i] end
  end
  B[:,pinv] = copy(A)
  offst = orders.+1; offst = [ prod(offst[1:i-1]) for i=1:length(offst)]
  return B*offst.+1
end

# nface to polytope cartesian index change of basis and inverse
function nfaceperms(nface)
  pd = length(nface.extrusion)
  e = nface.extrusion
  c=0; p=[]
  for i=1:pd
    (e[i]!=0) ? (c+=1; p=[p...,c]) : p=[p...,0]
  end
  c=0; pinv=[]
  for i=1:pd
    (p[i]!=0) ? (c+=1; pinv=[pinv...,i]) : 0
  end
  return [p,pinv]
end

# 1-dim node coordinates
function nodescoordinates(order::Int; nodestype::String="Equispaced")
  @assert ((nodestype=="Equispaced") | (nodestype=="Chebyshev")) "Node type not implemented"
  ordp1 = order+1
  if nodestype == "Chebyshev"
    nodescoordinates = [ cos((i-1)*pi/order) for i=1:ordp1]
  elseif nodestype == "Equispaced"
    (order != 0) ? nodescoordinates = (1/order)*[ i-1 for i=1:ordp1] : nodescoordinates = [0.0]
  end
  return nodescoordinates
end

@generated function cartesianindexmatrix!(A::Array{Array{T,M},N}) where {T,M,N}
  quote
    @nloops $N i A begin (@nref $N A i) = [((@ntuple $N i).-1)...] end
  end
end

end # module Polytopes
